//! `pleamar-describe-snap`, the port of
//! `files/pleamar/scripts/describe-snap.sh`.
//!
//! Start one scene hermetically (or through `systemd-run --user`), wait for its
//! socket, read the agent tree until two reads agree, mask the host-dependent
//! lines and either write `tests/<scene>.describe.txt` (`--update`) or diff the
//! canonical tree against it.

use std::env;
use std::ffi::OsString;
use std::fs::{self, File};
use std::io::Write;
use std::os::unix::fs::FileTypeExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use crate::ctx::{Ctx, Halt};
use crate::proc;
use crate::scene;
use crate::text;
use crate::usage;

pub struct Options {
    pub update: bool,
    pub live: bool,
    pub systemd: bool,
    pub keep_tmp: bool,
    pub soft: bool,
    pub timeout: String,
    pub scene: Option<String>,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            update: false,
            live: false,
            systemd: false,
            keep_tmp: false,
            soft: false,
            timeout: "15".to_string(),
            scene: None,
        }
    }
}

pub enum Parsed {
    Help,
    Run(Options),
}

pub fn parse_args(args: &[String]) -> Result<Parsed, Halt> {
    let mut options = Options::default();
    let mut index = 0usize;
    while index < args.len() {
        let argument = &args[index];
        match argument.as_str() {
            "--update" => {
                options.update = true;
                index += 1;
            }
            "--timeout" => {
                options.timeout = need_value(args, index, "--timeout needs a number")?;
                index += 2;
            }
            "--scene" => {
                if options.scene.is_some() {
                    return Err(Halt::Die("more than one scene given".to_string()));
                }
                options.scene = Some(need_value(args, index, "--scene needs a scene name")?);
                index += 2;
            }
            "--live" => {
                options.live = true;
                index += 1;
            }
            "--systemd" => {
                options.systemd = true;
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
    require_uint(&options.timeout, "--timeout")?;
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
    print!("{}", usage::DESCRIBE_SNAP);
}

struct Setup {
    live_runtime: String,
    live_display: String,
}

struct Runner {
    pid: Option<u32>,
    unit: Option<String>,
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
    let jq = ctx.resolve_bin("jq");

    let setup = setup_env(ctx, options.live, options.systemd)?;
    crate::env::apply_soft(ctx, options.soft);
    let scene = match scene::resolve(ctx, options.scene.as_deref()) {
        Some(scene) => scene,
        None => {
            return ctx.die("cannot resolve the scene (pass a name like 'proof' or a .plm path)")
        }
    };
    let timeout: u64 = options.timeout.parse().unwrap_or(1);
    let mut runner = match start_runner(
        ctx,
        &pleamar,
        pleamar_wm.as_deref(),
        &scene,
        timeout + 15,
        options.live,
        setup.live_display.as_str(),
        setup.live_runtime.as_str(),
        options.systemd,
    )? {
        Some(runner) => runner,
        None => {
            return ctx.die(format!(
                "no scene runner available for a hermetic run: pleamar-wm not found (PLEAMAR_WM_BIN='{wm_name}'); pass --live to start the scene in the current session, or install pleamar-wm"
            ))
        }
    };

    let wait = wait_for_socket(
        ctx,
        &pleamar,
        &scene.name,
        timeout,
        &runner,
        setup.live_runtime.as_str(),
    );
    if wait == 2 {
        ctx.say("the runner exited before the scene answered");
        show_log_tail(ctx, &ctx.temp().join("scene.log"));
        return ctx.die(format!(
            "scene '{}' never came up (see log above; --keep-tmp keeps the sandbox)",
            scene.name
        ));
    }
    if wait != 0 {
        ctx.say(format!(
            "the scene did not answer 'describe' within {}s",
            options.timeout
        ));
        show_log_tail(ctx, &ctx.temp().join("scene.log"));
        return ctx.fail(format!(
            "scene '{}' never answered (see log above; --keep-tmp keeps the sandbox)",
            scene.name
        ));
    }

    let temp = ctx.temp().to_path_buf();
    let raw = temp.join("describe.raw");
    let old = temp.join("old.json");
    let new = temp.join("new.json");
    let previous = temp.join("preview.json");
    let describe_error = temp.join("describe.err");
    let jq_error = temp.join("jq.err");

    if !capture_once(
        &pleamar,
        &scene.name,
        &raw,
        &describe_error,
        &jq_error,
        &previous,
        jq.as_deref(),
    ) {
        describe_failed(ctx, &temp);
        return ctx.die("could not capture the agent tree");
    }
    let mut tries = 0usize;
    loop {
        tries += 1;
        if !capture_once(
            &pleamar,
            &scene.name,
            &raw,
            &describe_error,
            &jq_error,
            &new,
            jq.as_deref(),
        ) {
            describe_failed(ctx, &temp);
            return ctx.die("could not capture the agent tree");
        }
        if text::same_file(&previous, &new) {
            break;
        }
        if tries >= 10 {
            ctx.say(format!(
                "the tree was still moving after {tries} reads; using the last one"
            ));
            break;
        }
        if let Err(error) = fs::copy(&new, &previous) {
            return ctx.fail(format!(
                "cannot copy {} to {}: {error}",
                new.display(),
                previous.display()
            ));
        }
        proc::sleep("0.5");
    }

    if text::file_size(&new) == Some(0) {
        ctx.stderr_bytes(b"describe-snap: error: the agent tree could not be normalised:\n");
        if let Ok(bytes) = fs::read(&raw) {
            ctx.stderr_bytes(&text::head_lines(&bytes, 5));
        }
        return ctx.die("cannot snapshot the agent tree (--keep-tmp keeps the raw output)");
    }

    let snap = ctx
        .project
        .join("tests")
        .join(format!("{}.describe.txt", scene.name));
    stop_scene(
        ctx,
        &pleamar,
        &scene.name,
        &mut runner,
        setup.live_runtime.as_str(),
    );

    if options.update {
        if snap.is_file() {
            if !text::canonicalize(&snap, jq.as_deref(), &old, None).unwrap_or(false) {
                return ctx.fail(format!(
                    "the committed snapshot {} does not parse as its own format; fix it by hand or delete it and re-run with --update",
                    snap.display()
                ));
            }
            if text::same_file(&old, &new) {
                ctx.say(format!("snapshot unchanged: {}", snap.display()));
                return Ok(0);
            }
            drift_summary(ctx, &old, &new, jq.as_deref())?;
        }
        let tests = ctx.project.join("tests");
        if let Err(error) = fs::create_dir_all(&tests) {
            return ctx.fail(format!("cannot create {}: {error}", tests.display()));
        }
        let snap_tmp = PathBuf::from(format!("{}.tmp.{}", snap.display(), std::process::id()));
        ctx.snap_tmp = Some(snap_tmp.clone());
        if let Err(error) = fs::copy(&new, &snap_tmp) {
            return ctx.fail(format!("cannot write {}: {error}", snap_tmp.display()));
        }
        if let Err(error) = fs::rename(&snap_tmp, &snap) {
            return ctx.fail(format!("cannot replace {}: {error}", snap.display()));
        }
        ctx.snap_tmp = None;
        let bytes = text::file_size(&snap).unwrap_or(0);
        ctx.say(format!("wrote {} ({bytes} bytes)", snap.display()));
        return Ok(0);
    }

    if !snap.is_file() {
        return ctx.fail(format!(
            "no committed snapshot at {}; run: describe-snap.sh --update {}",
            snap.display(),
            scene.name
        ));
    }
    if !text::canonicalize(&snap, jq.as_deref(), &old, None).unwrap_or(false) {
        return ctx.fail(format!(
            "the committed snapshot {} does not parse as its own format; regenerate it with --update",
            snap.display()
        ));
    }
    if text::same_file(&old, &new) {
        ctx.say(format!("snapshot matches: {}", snap.display()));
        return Ok(0);
    }
    drift_summary(ctx, &old, &new, jq.as_deref())?;
    ctx.fail(format!(
        "describe tree drifted from {} (review the drift above; --update rewrites it)",
        snap.display()
    ))
}

fn env_or(name: &str, default: &str) -> String {
    match env::var(name) {
        Ok(value) if !value.is_empty() => value,
        _ => default.to_string(),
    }
}

fn setup_env(ctx: &mut Ctx, live: bool, systemd: bool) -> Result<Setup, Halt> {
    let live_display = env::var("WAYLAND_DISPLAY").unwrap_or_default();
    let live_runtime = match env::var("XDG_RUNTIME_DIR") {
        Ok(value) if !value.is_empty() => value,
        _ => format!("/run/user/{}", crate::env::user_id()),
    };
    let temp = crate::env::mktemp(ctx.tool)?;
    ctx.temp = Some(temp.clone());
    if live {
        ctx.warn("using the ambient environment (--live)");
        return Ok(Setup {
            live_runtime,
            live_display,
        });
    }
    let mut compositor = live_display.clone();
    if systemd && !compositor.is_empty() && !compositor.starts_with('/') {
        compositor = format!("{live_runtime}/{compositor}");
    }
    if let Err(error) = crate::env::create_sandbox(&temp) {
        return ctx.fail(format!("cannot create the sandbox: {error}"));
    }
    crate::env::enter_sandbox(&temp);
    if systemd && !compositor.is_empty() {
        env::set_var("WAYLAND_DISPLAY", &compositor);
        ctx.say(format!(
            "hermetic files, the live compositor ({compositor}), run through systemd-run"
        ));
    }
    ctx.say(format!("hermetic environment under {}", temp.display()));
    Ok(Setup {
        live_runtime,
        live_display: compositor,
    })
}

#[allow(clippy::too_many_arguments)]
fn start_runner(
    ctx: &mut Ctx,
    pleamar: &str,
    pleamar_wm: Option<&str>,
    scene: &scene::Scene,
    budget: u64,
    live: bool,
    live_display: &str,
    live_runtime: &str,
    systemd: bool,
) -> Result<Option<Runner>, Halt> {
    let scene_log = ctx.temp().join("scene.log");
    if live && env::var("WAYLAND_DISPLAY").map_or(false, |value| !value.is_empty()) {
        ctx.say("starting the scene in the current session (--live)");
        let mut command = Command::new(pleamar);
        command
            .arg("--scene")
            .arg(&scene.file)
            .arg("--no-hud")
            .arg("--seconds")
            .arg(budget.to_string());
        let pid = ctx
            .spawn_log(proc::setsid(command), &scene_log)
            .map_err(|error| Halt::Fail(format!("cannot start the scene: {error}")))?;
        return Ok(Some(Runner {
            pid: Some(pid),
            unit: None,
        }));
    }
    if systemd {
        if live_display.is_empty() {
            ctx.say("--systemd needs a compositor and WAYLAND_DISPLAY is unset");
            return Ok(None);
        }
        let unit = format!("pleamar-snap-{}-{}", scene.name, std::process::id());
        let scene_runtime = env::var("XDG_RUNTIME_DIR").unwrap_or_default();
        let mut arguments: Vec<OsString> = vec![
            "--user".into(),
            format!("--unit={unit}").into(),
            "--collect".into(),
            "--quiet".into(),
            format!("--property=StandardOutput=append:{}", scene_log.display()).into(),
            format!("--property=StandardError=append:{}", scene_log.display()).into(),
        ];
        for name in [
            "HOME",
            "XDG_CONFIG_HOME",
            "XDG_DATA_HOME",
            "XDG_CACHE_HOME",
            "XDG_STATE_HOME",
            "XDG_RUNTIME_DIR",
            "WAYLAND_DISPLAY",
        ] {
            let value = if name == "XDG_RUNTIME_DIR" {
                scene_runtime.clone()
            } else {
                env::var(name).unwrap_or_default()
            };
            arguments.push(format!("--setenv={name}={value}").into());
        }
        if let Ok(value) = env::var("PLEAMAR_CONFIG") {
            if !value.is_empty() {
                arguments.push(format!("--setenv=PLEAMAR_CONFIG={value}").into());
            }
        }
        if let Ok(value) = env::var("VK_ICD_FILENAMES") {
            if !value.is_empty() {
                arguments.push(format!("--setenv=VK_ICD_FILENAMES={value}").into());
            }
        }
        arguments.push(pleamar.into());
        arguments.push("--scene".into());
        arguments.push(scene.file.as_os_str().to_os_string());
        arguments.push("--no-hud".into());
        arguments.push("--seconds".into());
        arguments.push(budget.to_string().into());
        ctx.say(format!("starting the scene as {unit} (systemd-run --user)"));
        let mut command = Command::new("systemd-run");
        command
            .args(&arguments)
            .env("XDG_RUNTIME_DIR", live_runtime);
        let status = proc::status_append(command, &scene_log);
        match status {
            Ok(status) if status.success() => {
                return Ok(Some(Runner {
                    pid: None,
                    unit: Some(unit),
                }))
            }
            _ => return Ok(None),
        }
    }
    if let Some(pleamar_wm) = pleamar_wm {
        ctx.say("starting the scene in pleamar-wm headless");
        let autostart = ctx.temp().join("autostart");
        let content = format!("{pleamar} --scene {} --no-hud\n", scene.file.display());
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
        return Ok(Some(Runner {
            pid: Some(pid),
            unit: None,
        }));
    }
    if live {
        ctx.say("--live was given but WAYLAND_DISPLAY is unset");
    }
    Ok(None)
}

fn find_socket_dir(name: &str) -> Option<PathBuf> {
    let root = match env::var("XDG_RUNTIME_DIR") {
        Ok(value) if !value.is_empty() => PathBuf::from(value),
        _ => PathBuf::from("/tmp"),
    };
    let wanted = format!("{name}.sock");
    find_socket_in(&root, &wanted, 0)
}

fn find_socket_in(directory: &Path, wanted: &str, depth: usize) -> Option<PathBuf> {
    let entries = fs::read_dir(directory).ok()?;
    for entry in entries.flatten() {
        let path = entry.path();
        let file_type = match entry.file_type() {
            Ok(file_type) => file_type,
            Err(_) => continue,
        };
        if file_type.is_socket() && path.file_name().map(|name| name == wanted).unwrap_or(false) {
            return path.parent().map(Path::to_path_buf);
        }
        if depth < 1 && file_type.is_dir() {
            if let Some(found) = find_socket_in(&path, wanted, depth + 1) {
                return Some(found);
            }
        }
    }
    None
}

fn wait_for_socket(
    ctx: &mut Ctx,
    pleamar: &str,
    name: &str,
    limit: u64,
    runner: &Runner,
    live_runtime: &str,
) -> i32 {
    let mut step = 0u64;
    while step < limit * 4 {
        let has_sockets = env::var("PLEAMAR_SOCKETS").map_or(false, |value| !value.is_empty());
        if !has_sockets {
            if let Some(directory) = find_socket_dir(name) {
                env::set_var("PLEAMAR_SOCKETS", directory);
            }
        }
        let status = Command::new(pleamar)
            .args(["--say", name, "describe"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
        if status.map(|status| status.success()).unwrap_or(false) {
            return 0;
        }
        if let Some(pid) = runner.pid {
            if !ctx.alive(pid) {
                return 2;
            }
        }
        if runner.pid.is_none() {
            if let Some(unit) = runner.unit.as_deref() {
                let active = Command::new("systemctl")
                    .arg("--user")
                    .arg("is-active")
                    .arg("--quiet")
                    .arg(unit)
                    .env("XDG_RUNTIME_DIR", live_runtime)
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .status();
                if !active.map(|status| status.success()).unwrap_or(false) {
                    return 2;
                }
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

fn stop_scene(ctx: &mut Ctx, pleamar: &str, name: &str, runner: &mut Runner, live_runtime: &str) {
    let _ = Command::new(pleamar)
        .args(["--say", name, "quit"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    if let Some(pid) = runner.pid.take() {
        ctx.terminate(pid);
    }
    if let Some(unit) = runner.unit.take() {
        let _ = Command::new("systemctl")
            .arg("--user")
            .arg("stop")
            .arg(&unit)
            .env("XDG_RUNTIME_DIR", live_runtime)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
}

fn describe_failed(ctx: &Ctx, temp: &Path) {
    ctx.stderr_bytes(b"describe-snap: error: describe failed:\n");
    if let Ok(bytes) = fs::read(temp.join("describe.err")) {
        ctx.stderr_bytes(&text::head_lines(&bytes, 5));
    }
    show_log_tail(ctx, &temp.join("scene.log"));
}

fn capture_once(
    pleamar: &str,
    name: &str,
    raw: &Path,
    describe_error: &Path,
    jq_error: &Path,
    destination: &Path,
    jq: Option<&str>,
) -> bool {
    let stdout = match File::create(raw) {
        Ok(file) => file,
        Err(_) => return false,
    };
    let stderr = match File::create(describe_error) {
        Ok(file) => file,
        Err(_) => return false,
    };
    let status = Command::new(pleamar)
        .args(["--say", name, "describe", "json"])
        .stdout(Stdio::from(stdout))
        .stderr(Stdio::from(stderr))
        .status();
    let first = match status {
        Ok(status) if status.success() => text::first_byte(raw),
        _ => None,
    };
    if !matches!(first, Some(b'{') | Some(b'[')) {
        let stdout = match File::create(raw) {
            Ok(file) => file,
            Err(_) => return false,
        };
        let stderr = match File::create(describe_error) {
            Ok(file) => file,
            Err(_) => return false,
        };
        let status = Command::new(pleamar)
            .args(["--say", name, "describe"])
            .stdout(Stdio::from(stdout))
            .stderr(Stdio::from(stderr))
            .status();
        if !status.map(|status| status.success()).unwrap_or(false) {
            return false;
        }
    }
    text::canonicalize(raw, jq, destination, Some(jq_error)).unwrap_or(false)
}

fn jq_keys(jq: &str, path: &Path) -> Vec<u8> {
    let output = Command::new(jq)
        .args(["-r", "keys_unsorted[]"])
        .arg(path)
        .stderr(Stdio::null())
        .output();
    output.map(|output| output.stdout).unwrap_or_default()
}

fn jq_has(jq: &str, path: &Path, key: &str) -> bool {
    Command::new(jq)
        .arg("-e")
        .arg("--arg")
        .arg("k")
        .arg(key)
        .arg("has($k)")
        .arg(path)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

fn jq_value(jq: &str, path: &Path, key: &str) -> String {
    let output = Command::new(jq)
        .arg("-cS")
        .arg("--arg")
        .arg("k")
        .arg(key)
        .arg(".[$k]")
        .arg(path)
        .stderr(Stdio::inherit())
        .output();
    match output {
        Ok(output) => proc::trim_newlines(&String::from_utf8_lossy(&output.stdout)).to_string(),
        Err(_) => String::new(),
    }
}

fn drift_summary(ctx: &Ctx, old: &Path, new: &Path, jq: Option<&str>) -> Result<(), Halt> {
    let diff = match text::unified_diff(old, new) {
        Ok(diff) => diff,
        Err(error) => return ctx.fail(format!("diff failed: {error}")),
    };
    let (added, removed) = text::added_removed(&diff);
    ctx.say(format!("drift: +{added}/-{removed} lines"));
    if let Some(jq) = jq.filter(|_| text::first_byte(old) == Some(b'{')) {
        let mut keys = jq_keys(jq, old);
        keys.extend(jq_keys(jq, new));
        let sorted = text::sort_unique(&keys).unwrap_or_default();
        for key in sorted.lines() {
            if !jq_has(jq, old, key) {
                ctx.say(format!("  + top-level key added: {key}"));
            } else if !jq_has(jq, new, key) {
                ctx.say(format!("  - top-level key removed: {key}"));
            } else if jq_value(jq, old, key) != jq_value(jq, new, key) {
                ctx.say(format!("  ~ top-level key changed: {key}"));
            }
        }
    }
    ctx.say("  first changed lines:");
    let mut stdout = std::io::stdout().lock();
    for line in text::first_changed_lines(&diff, 20) {
        let _ = writeln!(stdout, "{line}");
    }
    let _ = stdout.flush();
    let _ = old;
    Ok(())
}
