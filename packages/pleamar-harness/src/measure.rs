//! `pleamar-measure`, the port of `files/pleamar/scripts/measure.sh`.
//!
//! One scene for N seconds: `ps`/`/proc` samples, PSS, the scene's cgroup when
//! `--unit` names it, and `pleamar --report` in the same window. The external
//! commands keep the shell's argv; the TSV, Markdown report and log land where
//! the shell put them.

use std::env;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use crate::ctx::{Ctx, Halt};
use crate::proc;
use crate::scene;
use crate::text;
use crate::usage;

#[derive(Default)]
pub struct Options {
    pub scene: Option<String>,
    pub seconds: String,
    pub interval: String,
    pub unit: Option<String>,
    pub out: Option<PathBuf>,
    pub live: bool,
    pub keep_tmp: bool,
    pub soft: bool,
}

pub enum Parsed {
    Help,
    Run(Options),
}

/// Parse exactly like the shell's `while [ $# -gt 0 ]` loop.
pub fn parse_args(args: &[String]) -> Result<Parsed, Halt> {
    let mut options = Options {
        seconds: "20".to_string(),
        interval: "1".to_string(),
        ..Options::default()
    };
    let mut index = 0usize;
    while index < args.len() {
        let argument = &args[index];
        match argument.as_str() {
            "--scene" => {
                if options.scene.is_some() {
                    return Err(Halt::Die("more than one scene given".to_string()));
                }
                let value = need_value(args, index, "--scene needs a scene name")?;
                options.scene = Some(value);
                index += 2;
            }
            "--seconds" => {
                options.seconds = need_value(args, index, "--seconds needs a number")?;
                index += 2;
            }
            "--interval" => {
                options.interval = need_value(args, index, "--interval needs a number")?;
                index += 2;
            }
            "--unit" => {
                options.unit = Some(need_value(args, index, "--unit needs a unit name")?);
                index += 2;
            }
            "--out" => {
                options.out = Some(PathBuf::from(need_value(
                    args,
                    index,
                    "--out needs a directory",
                )?));
                index += 2;
            }
            "--live" => {
                options.live = true;
                index += 1;
            }
            "--keep-tmp" => {
                options.keep_tmp = true;
                index += 1;
            }
            "--soft" => {
                options.soft = true;
                index += 1;
            }
            "-h" | "--help" => return Ok(Parsed::Help),
            other if other.starts_with('-') => {
                return Err(Halt::Die(format!("unknown option: {other} (try --help)")));
            }
            other => {
                if options.scene.is_some() {
                    return Err(Halt::Die("more than one scene given".to_string()));
                }
                options.scene = Some(other.to_string());
                index += 1;
            }
        }
    }
    require_uint(&options.seconds, "--seconds")?;
    require_uint(&options.interval, "--interval")?;
    Ok(Parsed::Run(options))
}

fn need_value(args: &[String], index: usize, message: &str) -> Result<String, Halt> {
    match args.get(index + 1) {
        Some(value) => Ok(value.clone()),
        None => Err(Halt::Die(message.to_string())),
    }
}

fn require_uint(value: &str, name: &str) -> Result<(), Halt> {
    if value.is_empty() || !value.bytes().all(|byte| byte.is_ascii_digit()) {
        return Err(Halt::Die(format!(
            "{name} must be a positive integer (got '{value}')"
        )));
    }
    match value.parse::<u64>() {
        Ok(number) if number >= 1 => Ok(()),
        _ => Err(Halt::Die(format!("{name} must be at least 1"))),
    }
}

pub fn say_usage() {
    print!("{}", usage::MEASURE);
}

pub fn run(ctx: &mut Ctx, options: Options) -> Result<i32, Halt> {
    ctx.keep_tmp = options.keep_tmp;
    let pleamar_name = env_or("PLEAMAR_BIN", "pleamar");
    let wm_name = env_or("PLEAMAR_WM_BIN", "pleamar-wm");
    let pleamar = match ctx.resolve_bin(&pleamar_name) {
        Some(path) => path,
        None => {
            return ctx.die(format!(
                "pleamar not found (PLEAMAR_BIN='{pleamar_name}'). This harness never builds it: build/install pleamar, put it on PATH, or set PLEAMAR_BIN=/path/to/pleamar"
            ))
        }
    };
    let pleamar_wm = ctx.resolve_bin(&wm_name);
    let ticks = crate::env::clock_ticks();
    crate::env::apply_soft(ctx, options.soft);
    let scene = match scene::resolve(ctx, options.scene.as_deref()) {
        Some(scene) => scene,
        None => {
            return ctx.die("cannot resolve the scene (pass a name like 'proof' or a .plm path)")
        }
    };
    let seconds: u64 = options.seconds.parse().unwrap_or(1);
    let interval: u64 = options.interval.parse().unwrap_or(1);
    let out_dir = options
        .out
        .clone()
        .unwrap_or_else(|| ctx.project.join("tests/evidence"));

    let mut runner: Option<u32> = None;
    let (scene_pid, cgroup) = if let Some(unit) = options.unit.as_deref() {
        if env::var("XDG_RUNTIME_DIR").map_or(true, |value| value.is_empty()) {
            return ctx
                .die("--unit needs XDG_RUNTIME_DIR (the unit's session) to reach pleamar --say");
        }
        ctx.warn(format!(
            "measuring unit '{unit}' in the ambient session; the scene is not started or stopped"
        ));
        match unit_pid_and_cgroup(ctx, unit) {
            Some(found) => found,
            None => return ctx.die(format!("unit '{unit}' is not running (no MainPID)")),
        }
    } else {
        setup_env(ctx, options.live)?;
        runner = start_runner(
            ctx,
            &pleamar,
            pleamar_wm.as_deref(),
            &scene.file,
            seconds + 30,
            options.live,
        )?;
        let Some(started) = runner else {
            return ctx.die(format!(
                "no scene runner available for a hermetic run: pleamar-wm not found (PLEAMAR_WM_BIN='{wm_name}'); pass --live to start the scene in the current session, or --unit to measure a running unit"
            ));
        };
        let limit = seconds + 15;
        let wait = wait_for_socket(ctx, &pleamar, &scene.name, limit, Some(started));
        if wait == 2 {
            show_log_tail(ctx, &ctx.temp().join("scene.log"));
            return ctx.die(format!(
                "the runner exited before scene '{}' answered (see log above; --keep-tmp keeps the sandbox)",
                scene.name
            ));
        }
        if wait != 0 {
            show_log_tail(ctx, &ctx.temp().join("scene.log"));
            return ctx.fail(format!(
                "scene '{}' did not answer within {limit}s (see log above; --keep-tmp keeps the sandbox)",
                scene.name
            ));
        }
        let pid = match resolve_scene_pid(ctx, &pleamar, &scene.name, Some(started)) {
            Some(pid) => pid,
            None => {
                stop_scene(ctx, &pleamar, &scene.name, Some(started));
                return ctx.die(format!(
                    "could not resolve the pid of scene '{}' (tried the runner's own pid and its children)",
                    scene.name
                ));
            }
        };
        (pid, None)
    };

    if let Err(error) = fs::create_dir_all(&out_dir) {
        return ctx.fail(format!("cannot create {}: {error}", out_dir.display()));
    }
    let stamp = crate::env::date("+%Y-%m-%d");
    let tsv = out_dir.join(format!("{stamp}-{}.tsv", scene.name));
    let md = out_dir.join(format!("{stamp}-{}.md", scene.name));
    let log = out_dir.join(format!("{stamp}-{}.log", scene.name));
    if let Err(error) = fs::write(&log, b"") {
        return ctx.fail(format!("cannot write {}: {error}", log.display()));
    }
    let header = "t_s\tpid\trss_kb\tps_cpu_pct\tcpu_pct\tthreads\tpss_kb\tcg_mem_bytes\tcg_mem_peak_bytes\tcg_cpu_usec\tcg_cpu_pct\n";
    if let Err(error) = fs::write(&tsv, header) {
        return ctx.fail(format!("cannot write {}: {error}", tsv.display()));
    }

    ctx.say(format!(
        "measuring scene '{}' (pid {scene_pid}) for {}s, every {}s",
        scene.name, options.seconds, options.interval
    ));

    let mut report_command = Command::new(&pleamar);
    report_command
        .arg("--report")
        .arg(&scene.name)
        .arg("--seconds")
        .arg(&options.seconds)
        .arg("--out")
        .arg(&md);
    let report_pid = match ctx.spawn_log(report_command, &log) {
        Ok(pid) => pid,
        Err(error) => {
            return ctx.fail(format!(
                "cannot start pleamar --report: {error} (see {})",
                log.display()
            ))
        }
    };

    let mut tsv_file = match OpenOptions::new().append(true).open(&tsv) {
        Ok(file) => file,
        Err(error) => return ctx.fail(format!("cannot append to {}: {error}", tsv.display())),
    };
    let mut previous = Previous::default();
    let mut sample = 0u64;
    let mut scene_died = false;
    while sample <= seconds {
        if !pid_alive(&scene_pid) {
            scene_died = true;
            break;
        }
        let row = sample_row(
            &scene_pid,
            sample * interval,
            cgroup.as_deref(),
            &mut previous,
            &ticks,
        );
        if let Err(error) = writeln!(tsv_file, "{row}") {
            return ctx.fail(format!("cannot append to {}: {error}", tsv.display()));
        }
        sample += 1;
        if sample <= seconds {
            proc::sleep(&options.interval);
        }
    }
    drop(tsv_file);

    let report_rc = match ctx.wait(report_pid) {
        Some(status) => proc::exit_code(status),
        None => 127,
    };

    if options.unit.is_none() {
        stop_scene(ctx, &pleamar, &scene.name, runner);
    }

    ctx.say(format!("tsv: {}", tsv.display()));
    ctx.say(format!("md:  {}", md.display()));
    ctx.say(format!("log: {}", log.display()));
    println!();
    let table_rc = print_table(ctx, &tsv);
    if let Some(code) = table_rc {
        return Ok(code);
    }
    println!();
    if md.is_file() {
        let first = fs::read(&md)
            .ok()
            .map(|bytes| first_line(&bytes))
            .unwrap_or_default();
        ctx.say(format!("report: {first}"));
    }
    let samples = text::count_lines(&fs::read(&tsv).unwrap_or_default()).saturating_sub(1);
    if scene_died {
        return ctx.fail(format!(
            "scene process {scene_pid} exited during measurement ({samples} samples written to {})",
            tsv.display()
        ));
    }
    if report_rc != 0 {
        return ctx.fail(format!(
            "pleamar --report failed (exit {report_rc}; see {})",
            log.display()
        ));
    }
    ctx.say(format!("ok: {samples} samples in {}", tsv.display()));
    Ok(0)
}

fn env_or(name: &str, default: &str) -> String {
    match env::var(name) {
        Ok(value) if !value.is_empty() => value,
        _ => default.to_string(),
    }
}

fn pid_alive(pid: &str) -> bool {
    pid.parse::<u32>().map(proc::proc_exists).unwrap_or(false)
}

fn setup_env(ctx: &mut Ctx, live: bool) -> Result<(), Halt> {
    let temp = crate::env::mktemp(ctx.tool)?;
    ctx.temp = Some(temp.clone());
    if live {
        ctx.warn("using the ambient environment (--live)");
        return Ok(());
    }
    if let Err(error) = crate::env::create_sandbox(&temp) {
        return ctx.fail(format!("cannot create the sandbox: {error}"));
    }
    crate::env::enter_sandbox(&temp);
    ctx.say(format!("hermetic environment under {}", temp.display()));
    Ok(())
}

fn start_runner(
    ctx: &mut Ctx,
    pleamar: &str,
    pleamar_wm: Option<&str>,
    scene_file: &Path,
    budget: u64,
    live: bool,
) -> Result<Option<u32>, Halt> {
    let scene_log = ctx.temp().join("scene.log");
    if live && env::var("WAYLAND_DISPLAY").map_or(false, |value| !value.is_empty()) {
        ctx.say("starting the scene in the current session (--live)");
        let mut command = Command::new(pleamar);
        command
            .arg("--scene")
            .arg(scene_file)
            .arg("--no-hud")
            .arg("--seconds")
            .arg(budget.to_string());
        let pid = ctx
            .spawn_log(proc::setsid(command), &scene_log)
            .map_err(|error| Halt::Fail(format!("cannot start the scene: {error}")))?;
        return Ok(Some(pid));
    }
    if let Some(pleamar_wm) = pleamar_wm {
        ctx.say("starting the scene in pleamar-wm headless");
        let autostart = ctx.temp().join("autostart");
        let content = format!("{pleamar} --scene {} --no-hud\n", scene_file.display());
        if let Err(error) = fs::write(&autostart, content) {
            return ctx.fail(format!("cannot write {}: {error}", autostart.display()));
        }
        let mut command = Command::new(pleamar_wm);
        command
            .arg("headless")
            .arg("--seconds")
            .arg(budget.to_string())
            .env("PLEAMAR_WM_AUTOSTART", &autostart)
            .env("PLEAMAR_HEADLESS_AT", "1")
            .env("PLEAMAR_HEADLESS_PNG", ctx.temp().join("headless.png"));
        let pid = ctx
            .spawn_log(proc::setsid(command), &scene_log)
            .map_err(|error| Halt::Fail(format!("cannot start pleamar-wm: {error}")))?;
        return Ok(Some(pid));
    }
    if live {
        ctx.say("--live was given but WAYLAND_DISPLAY is unset");
        return Ok(None);
    }
    Ok(None)
}

fn wait_for_socket(
    ctx: &mut Ctx,
    pleamar: &str,
    name: &str,
    limit: u64,
    runner: Option<u32>,
) -> i32 {
    let mut step = 0u64;
    while step < limit * 4 {
        let status = Command::new(pleamar)
            .args(["--say", name, "describe"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
        if status.map(|status| status.success()).unwrap_or(false) {
            return 0;
        }
        if let Some(pid) = runner {
            if !ctx.alive(pid) {
                return 2;
            }
        }
        proc::sleep("0.25");
        step += 1;
    }
    1
}

fn show_log_tail(ctx: &Ctx, log: &Path) {
    let mut err = std::io::stderr().lock();
    let _ = write!(err, "{}: last lines of {}:\n", ctx.tool, log.display());
    if let Ok(bytes) = fs::read(log) {
        let _ = err.write_all(&text::tail_lines(&bytes, 15));
    }
    let _ = err.flush();
}

fn stop_scene(ctx: &mut Ctx, pleamar: &str, name: &str, runner: Option<u32>) {
    let _ = Command::new(pleamar)
        .args(["--say", name, "quit"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    if let Some(pid) = runner {
        ctx.terminate(pid);
    }
}

/// `sed -n 's/.*pid \([0-9][0-9]*\).*/\1/p' | head -n 1`, including the
/// backtracking: the last `pid ` prefix that is followed by digits wins.
fn pid_from_hello(text: &str) -> Option<String> {
    let mut found = None;
    let mut from = 0usize;
    while let Some(offset) = text[from..].find("pid ") {
        let at = from + offset;
        let digits: String = text[at + 4..]
            .chars()
            .take_while(|character| character.is_ascii_digit())
            .collect();
        if !digits.is_empty() {
            found = Some(digits);
        }
        from = at + 4;
    }
    found
}

fn resolve_scene_pid(
    ctx: &mut Ctx,
    pleamar: &str,
    name: &str,
    runner: Option<u32>,
) -> Option<String> {
    let output = Command::new(pleamar)
        .args(["--say", name, "hello"])
        .stderr(Stdio::null())
        .output()
        .ok();
    if let Some(output) = output {
        if let Some(pid) = pid_from_hello(&String::from_utf8_lossy(&output.stdout)) {
            return Some(pid);
        }
    }
    if let Some(pid) = runner {
        for child in proc::children_of(pid) {
            if let Ok(bytes) = fs::read(format!("/proc/{child}/cmdline")) {
                let command = String::from_utf8_lossy(&bytes).replace('\0', " ");
                if command.contains("--scene") {
                    return Some(child.to_string());
                }
            }
        }
    }
    let _ = ctx;
    None
}

fn systemctl_value(unit: &str, property: &str, user: bool) -> String {
    let mut command = Command::new("systemctl");
    if user {
        command.arg("--user");
    }
    command
        .arg("show")
        .arg("-p")
        .arg(property)
        .arg("--value")
        .arg(unit)
        .stderr(Stdio::null());
    let output = command.output();
    match output {
        Ok(output) => proc::trim_newlines(&String::from_utf8_lossy(&output.stdout)).to_string(),
        Err(_) => String::new(),
    }
}

fn unit_pid_and_cgroup(ctx: &Ctx, unit: &str) -> Option<(String, Option<PathBuf>)> {
    let mut pid = systemctl_value(unit, "MainPID", true);
    if pid.is_empty() || pid == "0" {
        pid = systemctl_value(unit, "MainPID", false);
    }
    if pid.is_empty() || pid == "0" {
        return None;
    }
    let mut cgroup = systemctl_value(unit, "ControlGroup", true);
    if cgroup.is_empty() {
        cgroup = systemctl_value(unit, "ControlGroup", false);
    }
    let path = if cgroup.is_empty() {
        ctx.warn(format!(
            "no cgroup found for unit '{unit}'; cgroup columns will be empty"
        ));
        None
    } else {
        let root = match env::var("PLEAMAR_CGROUP_ROOT") {
            Ok(value) if !value.is_empty() => value,
            _ => "/sys/fs/cgroup".to_string(),
        };
        let candidate = PathBuf::from(format!("{root}{cgroup}"));
        if candidate.is_dir() {
            Some(candidate)
        } else {
            ctx.warn(format!(
                "cgroup directory {} does not exist; cgroup columns will be empty",
                candidate.display()
            ));
            None
        }
    };
    Some((pid, path))
}

#[derive(Default)]
struct Previous {
    cpu: Option<String>,
    time: Option<String>,
    cgroup_cpu: Option<String>,
}

fn read_trimmed(path: &Path) -> Option<String> {
    let bytes = fs::read(path).ok()?;
    Some(
        String::from_utf8_lossy(&bytes)
            .trim_end_matches('\n')
            .to_string(),
    )
}

fn sample_row(
    pid: &str,
    seconds: u64,
    cgroup: Option<&Path>,
    previous: &mut Previous,
    ticks: &str,
) -> String {
    let mut rss = "-".to_string();
    let mut ps_cpu = "-".to_string();
    let mut threads = "-".to_string();
    let output = Command::new("ps")
        .args(["-o", "rss=", "-o", "pcpu=", "-o", "nlwp=", "-p", pid])
        .stderr(Stdio::null())
        .output();
    if let Ok(output) = output {
        let stdout = String::from_utf8_lossy(&output.stdout);
        let line = stdout.lines().next().unwrap_or("");
        if !line.is_empty() {
            let fields: Vec<&str> = line.split_whitespace().collect();
            rss = fields.first().copied().unwrap_or("").to_string();
            ps_cpu = fields.get(1).copied().unwrap_or("").to_string();
            threads = fields.get(2).copied().unwrap_or("").to_string();
        }
    }

    let cpu_now = fs::read_to_string(format!("/proc/{pid}/stat"))
        .ok()
        .and_then(|text| {
            let line = text.lines().next()?;
            let fields: Vec<&str> = line.split_whitespace().collect();
            let user: u64 = fields
                .get(13)
                .and_then(|value| value.parse().ok())
                .unwrap_or(0);
            let system: u64 = fields
                .get(14)
                .and_then(|value| value.parse().ok())
                .unwrap_or(0);
            Some((user + system).to_string())
        });
    let now = crate::env::date("+%s.%N");

    let mut cpu_pct = "-".to_string();
    if let (Some(current), Some(prior)) = (cpu_now.as_deref(), previous.cpu.as_deref()) {
        if let (Some(current), Some(prior), Some(now), Some(then)) = (
            current.parse::<f64>().ok(),
            prior.parse::<f64>().ok(),
            now.parse::<f64>().ok(),
            previous
                .time
                .as_deref()
                .and_then(|value| value.parse::<f64>().ok()),
        ) {
            let delta = now - then;
            if delta > 0.0 {
                let hz = ticks.parse::<f64>().unwrap_or(0.0);
                cpu_pct = format!("{:.2}", (current - prior) / hz / delta * 100.0);
            }
        }
    }

    let pss = match fs::read_to_string(format!("/proc/{pid}/smaps_rollup")) {
        Ok(text) => {
            let mut total = 0u64;
            for line in text.lines() {
                if let Some(rest) = line.strip_prefix("Pss:") {
                    if let Some(value) = rest.split_whitespace().next() {
                        total += value.parse::<u64>().unwrap_or(0);
                    }
                }
            }
            total.to_string()
        }
        Err(_) => "-".to_string(),
    };

    let mut cgroup_mem = "-".to_string();
    let mut cgroup_peak = "-".to_string();
    let mut cgroup_cpu: Option<String> = None;
    let mut cgroup_pct = "-".to_string();
    if let Some(cgroup) = cgroup {
        if let Some(value) = read_trimmed(&cgroup.join("memory.current")) {
            if !value.is_empty() {
                cgroup_mem = value;
            }
        }
        if let Some(value) = read_trimmed(&cgroup.join("memory.peak")) {
            if !value.is_empty() {
                cgroup_peak = value;
            }
        }
        if let Ok(text) = fs::read_to_string(cgroup.join("cpu.stat")) {
            for line in text.lines() {
                if let Some(rest) = line.strip_prefix("usage_usec") {
                    if let Some(value) = rest.split_whitespace().next() {
                        cgroup_cpu = Some(value.to_string());
                    }
                    break;
                }
            }
        }
        if let (Some(current), Some(prior)) =
            (cgroup_cpu.as_deref(), previous.cgroup_cpu.as_deref())
        {
            if let (Some(current), Some(prior), Some(now), Some(then)) = (
                current.parse::<f64>().ok(),
                prior.parse::<f64>().ok(),
                now.parse::<f64>().ok(),
                previous
                    .time
                    .as_deref()
                    .and_then(|value| value.parse::<f64>().ok()),
            ) {
                let delta = now - then;
                if delta > 0.0 {
                    cgroup_pct = format!("{:.2}", (current - prior) / 10_000.0 / delta);
                }
            }
        }
    }

    previous.cpu = cpu_now;
    previous.time = Some(now);
    if let Some(value) = &cgroup_cpu {
        previous.cgroup_cpu = Some(value.clone());
    }

    format!(
        "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
        seconds,
        pid,
        rss,
        ps_cpu,
        cpu_pct,
        threads,
        pss,
        cgroup_mem,
        cgroup_peak,
        cgroup_cpu.unwrap_or_default(),
        cgroup_pct
    )
}

/// `column -t -s $'\t'` when it exists, `cat` otherwise. Returns the exit code
/// when the table printer failed (the shell died from `set -e`).
fn print_table(ctx: &Ctx, tsv: &Path) -> Option<i32> {
    if ctx.resolve_bin("column").is_some() {
        let status = Command::new("column")
            .arg("-t")
            .arg("-s")
            .arg("\t")
            .arg(tsv)
            .status();
        match status {
            Ok(status) if status.success() => None,
            Ok(status) => Some(proc::exit_code(status)),
            Err(_) => Some(1),
        }
    } else {
        match fs::read(tsv) {
            Ok(bytes) => {
                let mut stdout = std::io::stdout().lock();
                let _ = stdout.write_all(&bytes);
                let _ = stdout.flush();
                None
            }
            Err(_) => Some(1),
        }
    }
}

fn first_line(bytes: &[u8]) -> String {
    let text = String::from_utf8_lossy(bytes);
    text.lines().next().unwrap_or("").to_string()
}
