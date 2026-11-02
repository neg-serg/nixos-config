//! Sampling: procfs/sysfs parsing, the awk program's formulas and the JSON
//! objects it printed.
//!
//! Every function that reads procfs text takes the text as an argument, so the
//! tests feed it synthetic `/proc/stat`, `/proc/meminfo`, `/proc/swaps` and
//! `/proc/diskstats` documents instead of the live files. Discovery helpers
//! take the sysfs root as a parameter for the same reason.

use std::fs;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};

use crate::state;

pub const NO_GPU_ERROR: &str = "no readable /sys/class/drm/card*/device/gpu_busy_percent";
pub const NO_TEMP_ERROR: &str =
    "no hwmon k10temp/coretemp/zenpower temp1_input and no /sys/class/thermal/thermal_zone0/temp";

#[derive(Clone, Debug)]
pub struct ProcPaths {
    pub stat: PathBuf,
    pub meminfo: PathBuf,
    pub swaps: PathBuf,
    pub diskstats: PathBuf,
}

impl Default for ProcPaths {
    fn default() -> Self {
        Self {
            stat: PathBuf::from("/proc/stat"),
            meminfo: PathBuf::from("/proc/meminfo"),
            swaps: PathBuf::from("/proc/swaps"),
            diskstats: PathBuf::from("/proc/diskstats"),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CpuCounters {
    pub total: u64,
    pub idle: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MemInfo {
    pub total_kb: u64,
    pub available_kb: u64,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SwapCounters {
    pub total_kb: u64,
    pub used_kb: u64,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct DiskCounters {
    pub read_sectors: u64,
    pub write_sectors: u64,
}

/// The full sample plus the compact objects the subtopics carry. The shell
/// built the full line and then let `jq -c '.[$topic]'` re-serialize a
/// subtopic; jq 1.8 preserves the number literals, so embedding the already
/// formatted sub-objects reproduces those lines byte for byte.
#[derive(Clone, Debug)]
pub struct Sample {
    pub cpu: String,
    pub mem: String,
    pub swap: String,
    pub disk: String,
    pub gpu: String,
    pub temp: String,
    pub full: String,
}

impl Sample {
    pub fn data_for(&self, topic: &str) -> &str {
        match topic {
            "sysmon" => &self.full,
            "cpu" => &self.cpu,
            "mem" => &self.mem,
            "swap" => &self.swap,
            "disk" => &self.disk,
            "gpu" => &self.gpu,
            "temp" => &self.temp,
            // Topics are validated before a subscription exists.
            _ => &self.full,
        }
    }
}

/// Read the first line of a file the way awk's `getline line < path` did:
/// an unreadable file is `None`, an empty file is `Some("")`, and a final line
/// without a newline is still a line.
pub fn read_first(path: &Path) -> Option<String> {
    let file = fs::File::open(path).ok()?;
    let mut reader = BufReader::new(file);
    let mut line = String::new();
    match reader.read_line(&mut line) {
        Ok(0) => Some(String::new()),
        Ok(_) => {
            if line.ends_with('\n') {
                line.pop();
            }
            Some(line)
        }
        Err(_) => None,
    }
}

fn read_text(path: &Path) -> Option<String> {
    fs::read(path)
        .ok()
        .map(|bytes| String::from_utf8_lossy(&bytes).into_owned())
}

fn fields(line: &str) -> Vec<&str> {
    line.split(|character| character == ' ' || character == '\t')
        .filter(|field| !field.is_empty())
        .collect()
}

fn trim_leading_blanks(line: &str) -> &str {
    line.trim_start_matches(|character| character == ' ' || character == '\t')
}

/// awk's `to_number`: strip leading blanks, cut at the first character that
/// cannot start a number, require `^[+-]?[0-9]`, then convert the numeric
/// prefix with strtod semantics. `None` is awk's empty string.
pub fn to_number(value: &str) -> Option<f64> {
    let candidate = value.trim_start_matches(|character| character == ' ' || character == '\t');
    let cut = candidate
        .find(|character: char| {
            !(character.is_ascii_digit()
                || character == '.'
                || character == '+'
                || character == '-')
        })
        .unwrap_or(candidate.len());
    let candidate = &candidate[..cut];
    let bytes = candidate.as_bytes();

    let mut index = 0;
    let mut negative = false;
    if index < bytes.len() && (bytes[index] == b'+' || bytes[index] == b'-') {
        negative = bytes[index] == b'-';
        index += 1;
    }
    if index >= bytes.len() || !bytes[index].is_ascii_digit() {
        return None;
    }

    let mut number = 0.0_f64;
    while index < bytes.len() && bytes[index].is_ascii_digit() {
        number = number * 10.0 + (bytes[index] - b'0') as f64;
        index += 1;
    }
    if index < bytes.len() && bytes[index] == b'.' {
        index += 1;
        let mut scale = 0.1_f64;
        while index < bytes.len() && bytes[index].is_ascii_digit() {
            number += (bytes[index] - b'0') as f64 * scale;
            scale *= 0.1;
            index += 1;
        }
    }
    Some(if negative { -number } else { number })
}

/// awk reads procfs counters with `field + 0`: garbage is zero.
fn counter(field: &str) -> u64 {
    match to_number(field) {
        Some(number) if number >= 0.0 => number as u64,
        _ => 0,
    }
}

/// Encode a string as a JSON string literal. The shell escaped backslashes,
/// quotes, tabs and CR in `json_escape`; serde_json produces the same bytes for
/// those and also escapes the remaining control characters (the shell did not,
/// which could only happen with a pathological `--gpu-path`).
pub fn json_string(value: &str) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| "\"\"".to_string())
}

/// `/proc/stat`, first `cpu` line, fields 2..9; idle is fields 5+6.
pub fn parse_cpu(line: &str) -> Option<CpuCounters> {
    if !line.starts_with("cpu ") {
        return None;
    }
    let fields = fields(line);
    let mut total = 0_u64;
    let mut idle = 0_u64;
    let limit = fields.len().min(9);
    for index in 1..limit {
        let value = counter(fields[index]);
        total = total.saturating_add(value);
        // awk's 1-based fields 5 and 6 (idle, iowait).
        if index == 4 || index == 5 {
            idle = idle.saturating_add(value);
        }
    }
    if total > 0 {
        Some(CpuCounters { total, idle })
    } else {
        None
    }
}

/// `/proc/meminfo`: MemTotal and MemAvailable in kB. The last occurrence wins,
/// as it did in the awk loop.
pub fn parse_meminfo(text: &str) -> Option<MemInfo> {
    let mut total: Option<u64> = None;
    let mut available: Option<u64> = None;
    for line in text.split('\n') {
        let fields = fields(line);
        if fields.len() < 2 {
            continue;
        }
        match fields[0] {
            "MemTotal:" => total = Some(counter(fields[1])),
            "MemAvailable:" => available = Some(counter(fields[1])),
            _ => {}
        }
    }
    match (total, available) {
        (Some(total_kb), Some(available_kb)) if total_kb > 0 => Some(MemInfo {
            total_kb,
            available_kb,
        }),
        _ => None,
    }
}

/// `/proc/swaps`: every line after the header, Size and Used in kB.
pub fn parse_swaps(text: &str) -> SwapCounters {
    let mut counters = SwapCounters::default();
    for (index, line) in text.split('\n').enumerate() {
        if index == 0 {
            continue;
        }
        let fields = fields(line);
        if fields.len() >= 4 {
            counters.total_kb = counters.total_kb.saturating_add(counter(fields[2]));
            counters.used_kb = counters.used_kb.saturating_add(counter(fields[3]));
        }
    }
    counters
}

/// `/proc/diskstats`, devices matching the shell's regex, sectors read from
/// field 6 and written from field 10 (1-based).
pub fn parse_diskstats(text: &str) -> DiskCounters {
    let mut counters = DiskCounters::default();
    for line in text.split('\n') {
        let fields = fields(trim_leading_blanks(line));
        if fields.len() >= 10 && is_disk_device(fields[2]) {
            counters.read_sectors = counters.read_sectors.saturating_add(counter(fields[5]));
            counters.write_sectors = counters.write_sectors.saturating_add(counter(fields[9]));
        }
    }
    counters
}

fn take_digits(value: &str) -> (&str, &str) {
    let end = value
        .bytes()
        .position(|byte| !byte.is_ascii_digit())
        .unwrap_or(value.len());
    (&value[..end], &value[end..])
}

fn letters_tail(value: &str) -> bool {
    !value.is_empty() && value.bytes().all(|byte| byte.is_ascii_lowercase())
}

/// `^(sd[a-z]+|nvme[0-9]+n[0-9]+|vd[a-z]+)$` without a regex dependency.
pub fn is_disk_device(name: &str) -> bool {
    if let Some(rest) = name.strip_prefix("sd") {
        return letters_tail(rest);
    }
    if let Some(rest) = name.strip_prefix("vd") {
        return letters_tail(rest);
    }
    if let Some(rest) = name.strip_prefix("nvme") {
        let (controller, rest) = take_digits(rest);
        if controller.is_empty() {
            return false;
        }
        let Some(rest) = rest.strip_prefix('n') else {
            return false;
        };
        let (namespace, rest) = take_digits(rest);
        return !namespace.is_empty() && rest.is_empty();
    }
    false
}

pub fn is_readable(path: &Path) -> bool {
    fs::File::open(path).is_ok()
}

fn entry_names(directory: &Path) -> Vec<String> {
    let Ok(entries) = fs::read_dir(directory) else {
        return Vec::new();
    };
    let mut names: Vec<String> = entries
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .collect();
    names.sort();
    names
}

fn is_card_name(name: &str) -> bool {
    match name.strip_prefix("card") {
        Some(rest) => match rest.as_bytes().first() {
            Some(byte) => byte.is_ascii_digit(),
            None => false,
        },
        None => false,
    }
}

/// `read -r variable < file` semantics: a final line without a newline is a
/// `read` failure, so the caller sees `None` (the shell assigned `0`/`""`).
fn read_line_strict(path: &Path) -> Option<String> {
    let file = fs::File::open(path).ok()?;
    let mut reader = BufReader::new(file);
    let mut line = String::new();
    match reader.read_line(&mut line) {
        Ok(0) | Err(_) => None,
        Ok(_) => {
            if line.ends_with('\n') {
                line.pop();
                Some(line)
            } else {
                None
            }
        }
    }
}

fn read_vram_total(path: &Path) -> u64 {
    let Some(line) = read_line_strict(path) else {
        return 0;
    };
    let trimmed = line.trim_matches(|character| character == ' ' || character == '\t');
    if trimmed.is_empty() || !trimmed.bytes().all(|byte| byte.is_ascii_digit()) {
        return 0;
    }
    trimmed.parse::<u64>().unwrap_or(0)
}

/// Largest-VRAM DRM card that exposes the readable `gpu_busy_percent`, the same
/// order the shell's glob produced.
pub fn discover_gpu(drm_directory: &Path) -> Option<PathBuf> {
    let mut best: Option<(PathBuf, u64)> = None;
    for name in entry_names(drm_directory) {
        if !is_card_name(&name) {
            continue;
        }
        let device = drm_directory.join(&name).join("device");
        let busy = device.join("gpu_busy_percent");
        if !is_readable(&busy) {
            continue;
        }
        let mut vram = 0;
        let vram_path = device.join("mem_info_vram_total");
        if is_readable(&vram_path) {
            vram = read_vram_total(&vram_path);
        }
        match &best {
            None => best = Some((busy, vram)),
            Some((_, best_vram)) if vram > *best_vram => best = Some((busy, vram)),
            Some(_) => {}
        }
    }
    best.map(|(path, _)| path)
}

/// `k10temp`/`coretemp`/`zenpower` `temp1_input`, else thermal zone 0.
pub fn discover_temp(hwmon_directory: &Path, thermal_zone0: &Path) -> Option<PathBuf> {
    for name in entry_names(hwmon_directory) {
        if !name.starts_with("hwmon") {
            continue;
        }
        let directory = hwmon_directory.join(&name);
        let name_path = directory.join("name");
        if !is_readable(&name_path) {
            continue;
        }
        let Some(hwmon_name) = read_line_strict(&name_path) else {
            continue;
        };
        let hwmon_name = hwmon_name.trim_matches(|character| character == ' ' || character == '\t');
        if matches!(hwmon_name, "k10temp" | "coretemp" | "zenpower") {
            let candidate = directory.join("temp1_input");
            if is_readable(&candidate) {
                return Some(candidate);
            }
        }
    }
    if is_readable(thermal_zone0) {
        return Some(thermal_zone0.to_path_buf());
    }
    None
}

fn format1(value: f64) -> String {
    format!("{value:.1}")
}

fn format2(value: f64) -> String {
    format!("{value:.2}")
}

fn error_object(message: &str) -> String {
    format!("{{\"err\":{}}}", json_string(message))
}

fn gpu_object(path: Option<&str>) -> String {
    let Some(path) = path.filter(|path| !path.is_empty()) else {
        return error_object(NO_GPU_ERROR);
    };
    let Some(value) = read_first(Path::new(path)).and_then(|line| to_number(&line)) else {
        return error_object(&format!("cannot read {path}"));
    };
    let mut percent = value;
    if percent < 0.0 {
        percent = 0.0;
    }
    if percent > 100.0 {
        percent = 100.0;
    }
    format!("{{\"percent\":{}}}", format1(percent))
}

fn temp_object(path: Option<&str>) -> String {
    let Some(path) = path.filter(|path| !path.is_empty()) else {
        return error_object(NO_TEMP_ERROR);
    };
    let Some(value) = read_first(Path::new(path)).and_then(|line| to_number(&line)) else {
        return error_object(&format!("cannot read {path}"));
    };
    let mut celsius = value / 1000.0;
    if celsius < 0.0 {
        celsius = 0.0;
    }
    let mut percent = (celsius - 30.0) / 70.0 * 100.0;
    if percent < 0.0 {
        percent = 0.0;
    }
    if percent > 100.0 {
        percent = 100.0;
    }
    format!(
        "{{\"celsius\":{},\"percent\":{}}}",
        format1(celsius),
        format1(percent)
    )
}

/// One sampling pass, exactly the awk `BEGIN` block: read the previous
/// counters from the state file, read the procfs/sysfs sources, compute, write
/// the new counters back, and return the data object.
///
/// `dt_ms` is `now - last_sample` in milliseconds (negative when the clock went
/// backwards); a non-positive value falls back to the CLI interval, as the awk
/// program did.
#[allow(clippy::too_many_arguments)]
pub fn sample(
    proc_paths: &ProcPaths,
    state_path: &Path,
    io_max_kibps: u64,
    gpu_path: Option<&str>,
    temp_path: Option<&str>,
    dt_ms: i64,
    interval_ms: u64,
    ts_secs: u64,
) -> Result<Sample, ()> {
    let previous = state::read(state_path);

    let cpu = read_first(&proc_paths.stat)
        .as_deref()
        .and_then(parse_cpu)
        .ok_or(())?;
    let meminfo_text = read_text(&proc_paths.meminfo).ok_or(())?;
    let meminfo = parse_meminfo(&meminfo_text).ok_or(())?;
    let swap = read_text(&proc_paths.swaps)
        .map(|text| parse_swaps(&text))
        .unwrap_or_default();
    let disk = read_text(&proc_paths.diskstats)
        .map(|text| parse_diskstats(&text))
        .unwrap_or_default();

    let mut previous_total = previous.cpu.map(|(total, _)| total);
    let mut previous_idle = previous.cpu.map(|(_, idle)| idle);
    if previous_total.map_or(true, |total| cpu.total < total) {
        previous_total = Some(cpu.total);
        previous_idle = Some(cpu.idle);
    }
    let mut previous_read = previous.disk.map(|(read, _)| read);
    let mut previous_write = previous.disk.map(|(_, write)| write);
    if previous_read.map_or(true, |read| disk.read_sectors < read) {
        previous_read = Some(disk.read_sectors);
        previous_write = Some(disk.write_sectors);
    }

    let mut dt = dt_ms as f64 / 1000.0;
    if dt <= 0.0 {
        dt = interval_ms as f64 / 1000.0;
    }

    let delta_total = cpu.total as f64 - previous_total.unwrap_or(0) as f64;
    let delta_idle = cpu.idle as f64 - previous_idle.unwrap_or(0) as f64;
    let mut cpu_percent = if delta_total > 0.0 {
        100.0 * (delta_total - delta_idle) / delta_total
    } else {
        0.0
    };
    if cpu_percent < 0.0 {
        cpu_percent = 0.0;
    }
    if cpu_percent > 100.0 {
        cpu_percent = 100.0;
    }

    let used_kb = meminfo.total_kb as i128 - meminfo.available_kb as i128;
    let used_kb = if used_kb < 0 { 0 } else { used_kb };
    let mem_percent = 100.0 * used_kb as f64 / meminfo.total_kb as f64;

    let swap_percent = if swap.total_kb > 0 {
        100.0 * swap.used_kb as f64 / swap.total_kb as f64
    } else {
        0.0
    };

    let read_kibps = (disk.read_sectors as f64 - previous_read.unwrap_or(0) as f64) * 0.5 / dt;
    let write_kibps = (disk.write_sectors as f64 - previous_write.unwrap_or(0) as f64) * 0.5 / dt;
    let read_kibps = if read_kibps < 0.0 { 0.0 } else { read_kibps };
    let write_kibps = if write_kibps < 0.0 { 0.0 } else { write_kibps };
    let mut disk_percent = 100.0 * (read_kibps + write_kibps) / io_max_kibps as f64;
    if disk_percent > 100.0 {
        disk_percent = 100.0;
    }

    let gpu = gpu_object(gpu_path);
    let temp = temp_object(temp_path);

    let cpu_json = format!("{{\"percent\":{}}}", format1(cpu_percent));
    let mem_json = format!(
        "{{\"used_gib\":{},\"total_gib\":{},\"percent\":{}}}",
        format2(used_kb as f64 / 1_048_576.0),
        format2(meminfo.total_kb as f64 / 1_048_576.0),
        format1(mem_percent)
    );
    let swap_json = format!(
        "{{\"available\":{},\"used_gib\":{},\"total_gib\":{},\"percent\":{}}}",
        if swap.total_kb > 0 { "true" } else { "false" },
        format2(swap.used_kb as f64 / 1_048_576.0),
        format2(swap.total_kb as f64 / 1_048_576.0),
        format1(swap_percent)
    );
    let disk_json = format!(
        "{{\"read_kibps\":{},\"write_kibps\":{},\"percent\":{}}}",
        format1(read_kibps),
        format1(write_kibps),
        format1(disk_percent)
    );

    let full = format!(
        "{{\"ts\":{ts},\"cpu\":{cpu}, \"mem\":{mem}, \"swap\":{swap}, \"disk\":{disk}, \"gpu\":{gpu},\"temp\":{temp}}}",
        ts = ts_secs,
        cpu = cpu_json,
        mem = mem_json,
        swap = swap_json,
        disk = disk_json,
        gpu = gpu,
        temp = temp,
    );

    // The awk program wrote the counters after printing the data; a failed
    // write made it exit non-zero, which the shell turned into a sample error.
    state::write(
        state_path,
        (cpu.total, cpu.idle),
        (disk.read_sectors, disk.write_sectors),
    )
    .map_err(|_| ())?;

    Ok(Sample {
        cpu: cpu_json,
        mem: mem_json,
        swap: swap_json,
        disk: disk_json,
        gpu,
        temp,
        full,
    })
}

/// Seed the counters once at start-up: the first emitted sample then covers a
/// real interval. The shell did this with a discarded awk run; like that run,
/// nothing is written when `/proc/stat` or `/proc/meminfo` is unreadable.
pub fn seed_state(proc_paths: &ProcPaths, state_path: &Path) {
    let Some(cpu) = read_first(&proc_paths.stat).as_deref().and_then(parse_cpu) else {
        return;
    };
    let Some(meminfo_text) = read_text(&proc_paths.meminfo) else {
        return;
    };
    if parse_meminfo(&meminfo_text).is_none() {
        return;
    }
    let disk = read_text(&proc_paths.diskstats)
        .map(|text| parse_diskstats(&text))
        .unwrap_or_default();
    let _ = state::write(
        state_path,
        (cpu.total, cpu.idle),
        (disk.read_sectors, disk.write_sectors),
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::{write_file, TempDir};

    fn fixture(directory: &TempDir) -> ProcPaths {
        ProcPaths {
            stat: write_file(directory.path(), "stat", "cpu  100 20 30 400 50 10 5 5 0 0\n"),
            meminfo: write_file(
                directory.path(),
                "meminfo",
                "MemTotal:        8000000 kB\nMemFree: 100 kB\nMemAvailable:    2000000 kB\n",
            ),
            swaps: write_file(
                directory.path(),
                "swaps",
                "Filename\t\t\t\tType\t\tSize\t\tUsed\t\tPriority\n/swapfile                               file\t\t1000000\t\t250000\t\t-2\n",
            ),
            diskstats: write_file(
                directory.path(),
                "diskstats",
                "   8       0 sda 10 0 1000 0 10 0 2000 0 0 0 0\n",
            ),
        }
    }

    #[test]
    fn to_number_matches_awk() {
        assert_eq!(to_number("37"), Some(37.0));
        assert_eq!(to_number("  45.5"), Some(45.5));
        assert_eq!(to_number("12.3abc"), Some(12.3));
        assert_eq!(to_number("1-2"), Some(1.0));
        assert_eq!(to_number("+7"), Some(7.0));
        assert_eq!(to_number("5."), Some(5.0));
        assert_eq!(to_number("12.34.56"), Some(12.34));
        assert_eq!(to_number(".5"), None);
        assert_eq!(to_number(""), None);
        assert_eq!(to_number("abc"), None);
        assert_eq!(to_number("-"), None);
        assert!(to_number("-0").expect("number").is_sign_negative());
    }

    #[test]
    fn cpu_line_fields_2_to_9_and_idle_5_plus_6() {
        let counters = parse_cpu("cpu  100 20 30 400 50 10 5 5 0 0\n").expect("cpu");
        assert_eq!(
            counters,
            CpuCounters {
                total: 620,
                idle: 450,
            }
        );
        assert_eq!(parse_cpu("cpu0 1 2 3 4 5 6 7 8"), None);
        assert_eq!(parse_cpu("cpu 0 0 0 0 0 0 0 0"), None);
    }

    #[test]
    fn meminfo_requires_total_and_available() {
        let parsed = parse_meminfo("MemTotal: 1000 kB\nMemAvailable: 400 kB\n").expect("mem");
        assert_eq!(parsed.total_kb, 1000);
        assert_eq!(parsed.available_kb, 400);
        assert_eq!(parse_meminfo("MemTotal: 0 kB\nMemAvailable: 0 kB\n"), None);
        assert_eq!(parse_meminfo("MemTotal: 1000 kB\n"), None);
        // The awk loop's last assignment wins for duplicate keys.
        assert_eq!(
            parse_meminfo("MemTotal: 1000 kB\nMemTotal: 2000 kB\nMemAvailable: 1 kB\n")
                .expect("mem")
                .total_kb,
            2000
        );
    }

    #[test]
    fn swaps_skip_the_header_and_sum_rows() {
        let text = "Filename Type Size Used Priority\n/dev/sda2 partition 100 20 -2\n/swapfile file 300 30 -3\n";
        assert_eq!(
            parse_swaps(text),
            SwapCounters {
                total_kb: 400,
                used_kb: 50,
            }
        );
        assert_eq!(parse_swaps(""), SwapCounters::default());
        assert_eq!(
            parse_swaps("Filename Type Size Used Priority\n"),
            SwapCounters::default()
        );
    }

    #[test]
    fn diskstats_device_filter_and_offsets() {
        let text = concat!(
            "   8       0 sda 10 0 1000 0 10 0 2000 0 0 0 0\n",
            "   8       1 sda1 10 0 9999 0 10 0 9999 0 0 0 0\n",
            " 259       0 nvme0n1 1 0 100 0 1 0 200 0 0 0 0\n",
            " 259       1 nvme0n1p1 1 0 5555 0 1 0 5555 0 0 0 0\n",
            " 254       0 vdb 1 0 10 0 1 0 20 0 0 0 0\n",
            "   7       0 loop0 1 0 1 0 1 0 1 0 0 0 0\n",
            " 253       0 dm-0 1 0 1 0 1 0 1 0 0 0 0\n",
        );
        assert_eq!(
            parse_diskstats(text),
            DiskCounters {
                read_sectors: 1110,
                write_sectors: 2220,
            }
        );
    }

    #[test]
    fn disk_device_names() {
        for name in ["sda", "sdz", "vda", "nvme0n1", "nvme12n34"] {
            assert!(is_disk_device(name), "{name} should match");
        }
        for name in ["sda1", "sd", "nvme0n1p1", "nvme0", "dm-0", "loop0", "vda1"] {
            assert!(!is_disk_device(name), "{name} should not match");
        }
    }

    #[test]
    fn finds_the_largest_vram_card() {
        let directory = TempDir::new("gpu-discovery");
        let drm = directory.path().join("drm");
        for (card, vram, busy) in [("card0", "100", true), ("card1", "500", true)] {
            let device = drm.join(card).join("device");
            if busy {
                write_file(&device, "gpu_busy_percent", "10\n");
            }
            write_file(&device, "mem_info_vram_total", &format!("{vram}\n"));
        }
        let found = discover_gpu(&drm).expect("gpu");
        assert_eq!(
            found,
            drm.join("card1").join("device").join("gpu_busy_percent")
        );
    }

    #[test]
    fn gpu_tie_keeps_the_first_card_in_glob_order() {
        let directory = TempDir::new("gpu-tie");
        let drm = directory.path().join("drm");
        for card in ["card0", "card1"] {
            let device = drm.join(card).join("device");
            write_file(&device, "gpu_busy_percent", "10\n");
            write_file(&device, "mem_info_vram_total", "100\n");
        }
        let found = discover_gpu(&drm).expect("gpu");
        assert_eq!(
            found,
            drm.join("card0").join("device").join("gpu_busy_percent")
        );
    }

    #[test]
    fn gpu_discovery_skips_unreadable_busy_files_and_missing_dirs() {
        let directory = TempDir::new("gpu-skip");
        let drm = directory.path().join("drm");
        write_file(&drm, "card0/device/mem_info_vram_total", "999\n");
        // Connector directories match `card[0-9]*` but have no `device`.
        write_file(&drm, "card1-DP-1/status", "connected\n");
        assert_eq!(discover_gpu(&drm), None);
        write_file(&drm, "card2/device/gpu_busy_percent", "5\n");
        // A VRAM file without a trailing newline is a `read` failure in the
        // shell, so the card counts as 0 MiB.
        write_file(&drm, "card2/device/mem_info_vram_total", "999");
        assert_eq!(
            discover_gpu(&drm),
            Some(drm.join("card2").join("device").join("gpu_busy_percent"))
        );
    }

    #[test]
    fn temp_prefers_known_hwmon_names_then_thermal_zone() {
        let directory = TempDir::new("temp-discovery");
        let hwmon = directory.path().join("hwmon");
        write_file(&hwmon, "hwmon0/name", "snd_hda_intel\n");
        write_file(&hwmon, "hwmon0/temp1_input", "40000\n");
        write_file(&hwmon, "hwmon1/name", "k10temp\n");
        write_file(&hwmon, "hwmon1/temp1_input", "45000\n");
        let thermal = directory.path().join("thermal_zone0/temp");
        write_file(directory.path(), "thermal_zone0/temp", "50000\n");
        assert_eq!(
            discover_temp(&hwmon, &thermal),
            Some(hwmon.join("hwmon1/temp1_input"))
        );

        let empty_hwmon = directory.path().join("empty-hwmon");
        fs::create_dir_all(&empty_hwmon).expect("mkdir");
        assert_eq!(discover_temp(&empty_hwmon, &thermal), Some(thermal));

        let missing_thermal = directory.path().join("missing/temp");
        assert_eq!(discover_temp(&empty_hwmon, &missing_thermal), None);
    }

    #[test]
    fn hwmon_name_without_newline_is_ignored() {
        let directory = TempDir::new("temp-no-newline");
        let hwmon = directory.path().join("hwmon");
        write_file(&hwmon, "hwmon0/name", "k10temp");
        write_file(&hwmon, "hwmon0/temp1_input", "45000\n");
        let thermal = directory.path().join("thermal_zone0/temp");
        write_file(directory.path(), "thermal_zone0/temp", "50000\n");
        assert_eq!(discover_temp(&hwmon, &thermal), Some(thermal));
    }

    fn sample_fixture(directory: &TempDir) -> (ProcPaths, PathBuf) {
        let proc_paths = fixture(directory);
        let state = directory.path().join("state");
        fs::write(&state, "520 400\n800 1800\n").expect("state");
        (proc_paths, state)
    }

    #[test]
    fn sample_matches_the_awk_format_and_formulas() {
        let directory = TempDir::new("sample-formulas");
        let (proc_paths, state_path) = sample_fixture(&directory);
        let gpu = write_file(directory.path(), "gpu", "37\n");
        let temp = write_file(directory.path(), "temp", "45000\n");

        let sampled = sample(
            &proc_paths,
            &state_path,
            10,
            Some(gpu.to_str().expect("utf8")),
            Some(temp.to_str().expect("utf8")),
            2000,
            1000,
            1_700_000_000,
        )
        .expect("sample");

        assert_eq!(
            sampled.full,
            concat!(
                "{\"ts\":1700000000,\"cpu\":{\"percent\":50.0}, ",
                "\"mem\":{\"used_gib\":5.72,\"total_gib\":7.63,\"percent\":75.0}, ",
                "\"swap\":{\"available\":true,\"used_gib\":0.24,\"total_gib\":0.95,\"percent\":25.0}, ",
                "\"disk\":{\"read_kibps\":50.0,\"write_kibps\":50.0,\"percent\":100.0}, ",
                "\"gpu\":{\"percent\":37.0},\"temp\":{\"celsius\":45.0,\"percent\":21.4}}"
            )
        );
        assert_eq!(sampled.cpu, "{\"percent\":50.0}");
        assert_eq!(
            fs::read_to_string(&state_path).expect("state"),
            "620 450\n1000 2000\n"
        );

        // A second sample over unchanged counters has zero deltas.
        let again = sample(
            &proc_paths,
            &state_path,
            10,
            Some(gpu.to_str().expect("utf8")),
            Some(temp.to_str().expect("utf8")),
            1000,
            1000,
            1_700_000_001,
        )
        .expect("sample");
        assert_eq!(
            again.cpu, "{\"percent\":0.0}",
            "unchanged jiffies must not invent load"
        );
        assert_eq!(
            again.disk,
            "{\"read_kibps\":0.0,\"write_kibps\":0.0,\"percent\":0.0}"
        );
    }

    #[test]
    fn no_gpu_or_temp_reports_the_shell_error_objects() {
        let directory = TempDir::new("sample-nosources");
        let (proc_paths, state_path) = sample_fixture(&directory);
        let sampled =
            sample(&proc_paths, &state_path, 512000, None, None, 1000, 1000, 1).expect("sample");
        assert_eq!(
            sampled.gpu,
            format!("{{\"err\":{}}}", json_string(NO_GPU_ERROR))
        );
        assert_eq!(
            sampled.temp,
            format!("{{\"err\":{}}}", json_string(NO_TEMP_ERROR))
        );

        let missing = directory.path().join("missing-source");
        let sampled = sample(
            &proc_paths,
            &state_path,
            512000,
            Some(missing.to_str().expect("utf8")),
            Some(missing.to_str().expect("utf8")),
            1000,
            1000,
            1,
        )
        .expect("sample");
        let expected = format!(
            "{{\"err\":{}}}",
            json_string(&format!("cannot read {}", missing.display()))
        );
        assert_eq!(sampled.gpu, expected);
        assert_eq!(sampled.temp, expected);
    }

    #[test]
    fn gpu_and_temp_are_clamped() {
        let directory = TempDir::new("sample-clamp");
        let (proc_paths, state_path) = sample_fixture(&directory);
        let gpu = write_file(directory.path(), "gpu", "-5\n");
        let temp = write_file(directory.path(), "temp", "150000\n");
        let sampled = sample(
            &proc_paths,
            &state_path,
            512000,
            Some(gpu.to_str().expect("utf8")),
            Some(temp.to_str().expect("utf8")),
            1000,
            1000,
            1,
        )
        .expect("sample");
        assert_eq!(sampled.gpu, "{\"percent\":0.0}");
        // 150 C: percent clamps at 100, celsius does not clamp upwards.
        assert_eq!(sampled.temp, "{\"celsius\":150.0,\"percent\":100.0}");
    }

    #[test]
    fn swap_unavailable_reports_zeroes() {
        let directory = TempDir::new("sample-noswap");
        let (proc_paths, state_path) = sample_fixture(&directory);
        fs::write(
            &proc_paths.swaps,
            "Filename\t\t\t\tType\t\tSize\t\tUsed\t\tPriority\n",
        )
        .expect("swaps");
        let sampled =
            sample(&proc_paths, &state_path, 512000, None, None, 1000, 1000, 1).expect("sample");
        assert_eq!(
            sampled.swap,
            "{\"available\":false,\"used_gib\":0.00,\"total_gib\":0.00,\"percent\":0.0}"
        );
    }

    #[test]
    fn counter_reset_rebaselines_instead_of_reporting_a_spike() {
        let directory = TempDir::new("sample-reset");
        let (proc_paths, state_path) = sample_fixture(&directory);
        fs::write(&proc_paths.stat, "cpu  1 0 0 1 0 0 0 0 0 0\n").expect("stat");
        fs::write(&proc_paths.diskstats, "8 0 sda 0 0 1 0 0 0 1 0 0 0 0\n").expect("disk");
        let sampled =
            sample(&proc_paths, &state_path, 512000, None, None, 1000, 1000, 1).expect("sample");
        assert_eq!(sampled.cpu, "{\"percent\":0.0}");
        assert_eq!(
            sampled.disk,
            "{\"read_kibps\":0.0,\"write_kibps\":0.0,\"percent\":0.0}"
        );
    }

    #[test]
    fn missing_proc_sources_fail_the_sample() {
        let directory = TempDir::new("sample-missing");
        let (mut proc_paths, state_path) = sample_fixture(&directory);
        proc_paths.stat = directory.path().join("missing-stat");
        assert!(
            sample(&proc_paths, &state_path, 512000, None, None, 1000, 1000, 1).is_err(),
            "a missing /proc/stat must fail the sample"
        );

        proc_paths.stat = write_file(directory.path(), "stat2", "cpu  10 0 0 5 0 0 0 0 0 0\n");
        proc_paths.meminfo = directory.path().join("missing-meminfo");
        assert!(
            sample(&proc_paths, &state_path, 512000, None, None, 1000, 1000, 1).is_err(),
            "a missing /proc/meminfo must fail the sample"
        );
    }

    #[test]
    fn seed_writes_the_baseline_only_when_cpu_and_mem_are_readable() {
        let directory = TempDir::new("seed");
        let proc_paths = fixture(&directory);
        let state_path = directory.path().join("seed-state");

        seed_state(&proc_paths, &state_path);
        assert_eq!(
            fs::read_to_string(&state_path).expect("state"),
            "620 450\n1000 2000\n"
        );

        let mut broken = proc_paths.clone();
        broken.meminfo = directory.path().join("missing-meminfo");
        let empty_state = directory.path().join("empty-state");
        seed_state(&broken, &empty_state);
        assert!(!empty_state.exists(), "no baseline without meminfo");
    }
}
