use anyhow::{bail, Context, Result};
use std::collections::{BTreeSet, HashMap};
use std::fs;

const BOOST_PATH: &str = "/sys/devices/system/cpu/cpufreq/boost";
const CPU_BASE: &str = "/sys/devices/system/cpu";

/// Run the `cpu boost` subcommand.
pub fn run_boost(action: &str) -> Result<()> {
    if !std::path::Path::new(BOOST_PATH).exists() {
        bail!("boost interface not found at {BOOST_PATH}");
    }

    match action {
        "status" => {
            let current = read_boost()?;
            println!("interface: cpufreq");
            println!("boost: {}", if current { "on" } else { "off" });
        }
        "on" | "off" | "toggle" => {
            require_root()?;
            let current = read_boost()?;
            let target = match action {
                "on" => true,
                "off" => false,
                "toggle" => !current,
                _ => unreachable!(),
            };
            fs::write(BOOST_PATH, if target { "1\n" } else { "0\n" })
                .context("writing boost sysfs file")?;
            println!(
                "boost: {} -> {}",
                if current { "on" } else { "off" },
                if target { "on" } else { "off" }
            );
        }
        other => bail!("unknown boost action: {other} (use status|on|off|toggle)"),
    }
    Ok(())
}

fn read_boost() -> Result<bool> {
    let val = fs::read_to_string(BOOST_PATH).context("reading boost sysfs file")?;
    Ok(val.trim() == "1")
}

/// Run the `cpu masks` subcommand.
pub fn run_masks() -> Result<()> {
    let groups = l3_cache_groups()?;
    if groups.is_empty() {
        bail!("no L3 cache info found; is sysfs available?");
    }

    // Find the group with the largest cache
    let (vcache_cpus, _) = groups
        .iter()
        .max_by_key(|(_, size)| *size)
        .context("no L3 groups found")?;

    // All online CPUs
    let all_online = read_cpu_list("online")?;
    // Non-VCache CPUs
    let vcache_set: BTreeSet<u32> = vcache_cpus.iter().copied().collect();
    let non_vcache: Vec<u32> = all_online
        .iter()
        .filter(|c| !vcache_set.contains(c))
        .copied()
        .collect();

    let vcache_str = compress_cpuset(vcache_cpus);
    let non_vcache_str = if non_vcache.is_empty() {
        String::new()
    } else {
        compress_cpuset(&non_vcache)
    };

    println!("VCACHE_CPUSET={vcache_str}");
    println!();
    println!("Suggested kernel params:");
    println!("  nohz_full={vcache_str}");
    println!("  rcu_nocbs={vcache_str}");
    println!("  isolcpus=managed,domain,{vcache_str}");
    if !non_vcache_str.is_empty() {
        println!("  irqaffinity={non_vcache_str}");
    }
    Ok(())
}

/// Read a cpulist (e.g. "0-3,8,10-11") from a sysfs file under CPU_BASE.
fn read_cpu_list(name: &str) -> Result<Vec<u32>> {
    let path = format!("{CPU_BASE}/{name}");
    let content = fs::read_to_string(&path).context(format!("reading {path}"))?;
    parse_cpuset(&content.trim())
}

/// Parse a cpulist like "0-3,8,10-11" into a sorted vec of integers.
fn parse_cpuset(s: &str) -> Result<Vec<u32>> {
    let mut cpus = BTreeSet::new();
    for part in s.split(',') {
        let part = part.trim();
        if part.is_empty() {
            continue;
        }
        if let Some((start, end)) = part.split_once('-') {
            let lo: u32 = start
                .trim()
                .parse()
                .context(format!("invalid cpulist range start: {start}"))?;
            let hi: u32 = end
                .trim()
                .parse()
                .context(format!("invalid cpulist range end: {end}"))?;
            for cpu in lo..=hi {
                cpus.insert(cpu);
            }
        } else {
            let cpu: u32 = part
                .parse()
                .context(format!("invalid cpulist entry: {part}"))?;
            cpus.insert(cpu);
        }
    }
    Ok(cpus.into_iter().collect())
}

/// Compress a sorted list of integers to range form: 0-3,8,10-11.
fn compress_cpuset(cpus: &[u32]) -> String {
    if cpus.is_empty() {
        return String::new();
    }
    let mut out = String::new();
    let mut iter = cpus.iter();
    let mut start = *iter.next().unwrap();
    let mut prev = start;
    for &cur in iter {
        if cur == prev + 1 {
            prev = cur;
            continue;
        }
        if !out.is_empty() {
            out.push(',');
        }
        if start == prev {
            out.push_str(&start.to_string());
        } else {
            out.push_str(&format!("{start}-{prev}"));
        }
        start = cur;
        prev = cur;
    }
    if !out.is_empty() {
        out.push(',');
    }
    if start == prev {
        out.push_str(&start.to_string());
    } else {
        out.push_str(&format!("{start}-{prev}"));
    }
    out
}

/// Parse size strings like "512K", "8M", "2G" -> bytes.
fn parse_size(s: &str) -> Option<u64> {
    let s = s.trim().to_uppercase();
    if let Some(rest) = s.strip_suffix('K') {
        rest.parse::<u64>().ok().map(|v| v * 1024)
    } else if let Some(rest) = s.strip_suffix('M') {
        rest.parse::<u64>().ok().map(|v| v * 1024 * 1024)
    } else if let Some(rest) = s.strip_suffix('G') {
        rest.parse::<u64>().ok().map(|v| v * 1024 * 1024 * 1024)
    } else {
        s.parse::<u64>().ok()
    }
}

/// Read all L3 cache groups: returns Vec<(cpus, size_in_bytes)>.
fn l3_cache_groups() -> Result<Vec<(Vec<u32>, u64)>> {
    let mut groups: HashMap<String, (Vec<u32>, u64)> = HashMap::new();

    for entry in fs::read_dir(CPU_BASE)? {
        let entry = entry?;
        let dirname = entry.file_name();
        let dirname = dirname.to_string_lossy();
        if !dirname.starts_with("cpu") {
            continue;
        }
        let idx_str = dirname.trim_start_matches("cpu");
        let _idx: u32 = match idx_str.parse() {
            Ok(i) => i,
            Err(_) => continue,
        };

        let index3 = entry.path().join("cache/index3");
        let size_file = index3.join("size");
        let share_file = index3.join("shared_cpu_list");
        if !size_file.exists() || !share_file.exists() {
            continue;
        }

        let size_content = fs::read_to_string(&size_file)?;
        let size = match parse_size(&size_content) {
            Some(s) => s,
            None => continue,
        };
        let shared_content = fs::read_to_string(&share_file)?;
        let cpus = parse_cpuset(&shared_content)?;
        let key = compress_cpuset(&cpus);
        if !groups.contains_key(&key) {
            groups.insert(key.clone(), (cpus, size));
        }
    }

    Ok(groups.into_values().collect())
}

fn require_root() -> Result<()> {
    if unsafe { libc::geteuid() } != 0 {
        bail!("must be root to change CPU boost state (try: sudo hwctl cpu boost ...)");
    }
    Ok(())
}
