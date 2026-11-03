//! `pleamar-rig`: a copy of the shell in a headless `pleamar-wm`, to look at and
//! poke without touching the desktop in use.
//!
//! The idea is the one a sibling pleamar shell (Vitreus, MIT) runs as
//! `dev/rig`: the whole `files/pleamar` tree is copied into a rig root with its
//! own HOME, XDG folders, runtime directory and log, a headless `pleamar-wm`
//! starts one scene from that copy, and the developer talks to it with
//! `pleamar --say`. Edits are re-copied with `sync` (the shell reloads them in
//! about two seconds), a picture is taken with `--png`/`--at`, and `stop` ends
//! it.
//!
//! What the copy does not share with the desktop: its config, data, cache,
//! state and runtime directories, and the compositor's own state (no Hyprland:
//! gaps, borders and the glass's blur cannot be seen here). What it does share:
//! the fonts, the network and any program the shell runs by name.
//!
//! External commands, as everywhere else in this crate: `pleamar`,
//! `pleamar-wm` and `kill`. Everything else (copying, paths, the pid file) is
//! in-process.

use std::env;
use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use crate::ctx::{Ctx, Halt};
use crate::proc;

pub const USAGE: &str = "\
pleamar-rig — a copy of the shell in a headless pleamar-wm

  pleamar-rig start [--scene NAME] [--seconds N] [--png FILE] [--at N] [--input SPEC]
  pleamar-rig sync
  pleamar-rig say SCENE CMD...
  pleamar-rig log [N]
  pleamar-rig stop
  pleamar-rig -h | --help

The rig root is $RIG (default /tmp/pleamar-rig): its own HOME, config, data,
cache, state, runtime directory and log. `start` copies files/pleamar there and
starts the scene in that copy; `sync` copies the tree again into the running
copy; `say` runs `pleamar --say SCENE ...` against the rig's socket; `log` prints
the end of its log (40 lines by default); `stop` ends it and removes the root.

  --scene NAME     the scene to start (default bar)
  --seconds N      how long the headless session lives (default 900)
  --png FILE       PLEAMAR_HEADLESS_PNG: save a picture of the rig's screen
  --at N           PLEAMAR_HEADLESS_AT: seconds into the session to take it
  --input SPEC     PLEAMAR_HEADLESS_INPUT: a mouse path, e.g. 900,40@2000 down@2500 up@2600

Exit: 0 done, 1 the command failed, 2 usage or no rig.
";

/// What `parse_args` decided.
pub enum Parsed {
    Help,
    Run(Options),
}

/// One `pleamar-rig` invocation.
pub struct Options {
    pub command: String,
    pub scene: String,
    pub seconds: u64,
    pub png: Option<String>,
    pub at: Option<String>,
    pub input: Option<String>,
    pub tail: usize,
    pub rest: Vec<String>,
}

/// Parse the argv the way the other harnesses do: the command first, then its
/// options; `-h`/`--help` anywhere prints the usage.
pub fn parse_args(args: &[String]) -> Result<Parsed, Halt> {
    if args.is_empty() {
        return Err(Halt::Die("no command (try --help)".to_string()));
    }
    let mut options = Options {
        command: args[0].clone(),
        scene: "bar".to_string(),
        seconds: 900,
        png: None,
        at: None,
        input: None,
        tail: 40,
        rest: Vec::new(),
    };
    if matches!(options.command.as_str(), "-h" | "--help" | "help") {
        return Ok(Parsed::Help);
    }
    if !matches!(
        options.command.as_str(),
        "start" | "sync" | "say" | "log" | "stop"
    ) {
        return Err(Halt::Die(format!(
            "unknown command '{}' (start, sync, say, log, stop)",
            options.command
        )));
    }
    let mut index = 1;
    while index < args.len() {
        let argument = &args[index];
        match argument.as_str() {
            "-h" | "--help" => return Ok(Parsed::Help),
            "--scene" | "--seconds" | "--png" | "--at" | "--input" => {
                let value = args
                    .get(index + 1)
                    .cloned()
                    .ok_or_else(|| Halt::Die(format!("{argument} needs a value")))?;
                match argument.as_str() {
                    "--scene" => options.scene = value,
                    "--seconds" => {
                        options.seconds = value.parse().map_err(|_| {
                            Halt::Die(format!("--seconds needs a number, not '{value}'"))
                        })?
                    }
                    "--png" => options.png = Some(value),
                    "--at" => options.at = Some(value),
                    "--input" => options.input = Some(value),
                    _ => unreachable!(),
                }
                index += 2;
            }
            _ => {
                options.rest.push(argument.clone());
                index += 1;
            }
        }
    }
    if options.command == "log" {
        if let Some(first) = options.rest.first() {
            options.tail = first.parse().unwrap_or(40);
        }
    }
    Ok(Parsed::Run(options))
}

/// The rig's folders, all under one root.
struct Rig {
    root: PathBuf,
}

impl Rig {
    fn from_env() -> Self {
        let root = match env::var("RIG") {
            Ok(value) if !value.is_empty() => PathBuf::from(value),
            _ => PathBuf::from("/tmp/pleamar-rig"),
        };
        Self { root }
    }

    fn conf(&self) -> PathBuf {
        self.root.join("conf")
    }
    fn shell(&self) -> PathBuf {
        self.conf().join("pleamar")
    }
    fn data(&self) -> PathBuf {
        self.root.join("data")
    }
    fn cache(&self) -> PathBuf {
        self.root.join("cache")
    }
    fn state(&self) -> PathBuf {
        self.root.join("state")
    }
    fn home(&self) -> PathBuf {
        self.root.join("home")
    }
    fn run(&self) -> PathBuf {
        self.root.join("run")
    }
    fn pleamar_config(&self) -> PathBuf {
        self.root.join("pleamar-config")
    }
    fn log(&self) -> PathBuf {
        self.root.join("log")
    }
    fn pid_file(&self) -> PathBuf {
        self.root.join("pid")
    }
    fn autostart(&self) -> PathBuf {
        self.root.join("autostart")
    }

    fn create(&self) -> std::io::Result<()> {
        for folder in [
            self.conf(),
            self.data(),
            self.cache(),
            self.state(),
            self.home(),
            self.run(),
            self.pleamar_config(),
        ] {
            fs::create_dir_all(folder)?;
        }
        fs::set_permissions(self.run(), fs::Permissions::from_mode(0o700))
    }

    fn shell_scene(&self, scene: &str) -> PathBuf {
        self.shell()
            .join("shells")
            .join(scene)
            .join(format!("{scene}.plm"))
    }
}

/// The environment a rig child sees: its own HOME and XDG folders, no live
/// display. `pleamar` finds the rig's socket through `XDG_RUNTIME_DIR`.
fn apply_env(command: &mut Command, rig: &Rig) {
    command
        .env("HOME", rig.home())
        .env("XDG_CONFIG_HOME", rig.conf())
        .env("XDG_DATA_HOME", rig.data())
        .env("XDG_CACHE_HOME", rig.cache())
        .env("XDG_STATE_HOME", rig.state())
        .env("XDG_RUNTIME_DIR", rig.run())
        .env("PLEAMAR_CONFIG", rig.pleamar_config())
        .env("PLEAMAR_ROOT", &rig.root);
    for variable in [
        "WAYLAND_DISPLAY",
        "WAYLAND_SOCKET",
        "DISPLAY",
        "HYPRLAND_INSTANCE_SIGNATURE",
    ] {
        command.env_remove(variable);
    }
}

fn resolve(ctx: &Ctx, fallback: &str, variable: &str) -> Result<String, Halt> {
    if let Ok(value) = env::var(variable) {
        if !value.is_empty() {
            return Ok(value);
        }
    }
    ctx.resolve_bin(fallback).ok_or_else(|| {
        Halt::Die(format!(
            "{fallback} not found: put it on PATH or set {variable}"
        ))
    })
}

fn copy_tree(source: &Path, destination: &Path) -> std::io::Result<usize> {
    let mut copied = 0;
    fs::create_dir_all(destination)?;
    for entry in fs::read_dir(source)? {
        let entry = entry?;
        let path = entry.path();
        let target = destination.join(entry.file_name());
        let metadata = fs::symlink_metadata(&path)?;
        if metadata.file_type().is_symlink() {
            let _ = fs::remove_file(&target);
            let link = fs::read_link(&path)?;
            std::os::unix::fs::symlink(link, &target)?;
        } else if metadata.is_dir() {
            copied += copy_tree(&path, &target)?;
        } else {
            fs::copy(&path, &target)?;
            copied += 1;
        }
    }
    Ok(copied)
}

fn read_pid(rig: &Rig) -> Option<u32> {
    let text = fs::read_to_string(rig.pid_file()).ok()?;
    text.trim().parse().ok()
}

fn running(rig: &Rig) -> Option<u32> {
    let pid = read_pid(rig)?;
    if proc::proc_exists(pid) {
        Some(pid)
    } else {
        None
    }
}

fn tail_lines(path: &Path, count: usize) -> std::io::Result<Vec<String>> {
    let text = fs::read_to_string(path)?;
    let lines: Vec<String> = text.lines().map(str::to_string).collect();
    let start = lines.len().saturating_sub(count);
    Ok(lines[start..].to_vec())
}

/// Run one rig command.
pub fn run(ctx: &mut Ctx, options: Options) -> Result<i32, Halt> {
    let rig = Rig::from_env();
    match options.command.as_str() {
        "start" => start(ctx, &rig, &options),
        "sync" => sync(ctx, &rig),
        "say" => say(ctx, &rig, &options),
        "log" => log(ctx, &rig, options.tail),
        "stop" => stop(ctx, &rig),
        _ => ctx.die("unknown command"),
    }
}

fn start(ctx: &mut Ctx, rig: &Rig, options: &Options) -> Result<i32, Halt> {
    if let Some(pid) = running(rig) {
        return ctx.fail(format!(
            "the rig is already running (pid {pid}; pleamar-rig stop first)"
        ));
    }
    // `project_root` answers the pleamar tree itself (`files/pleamar`), which is
    // what the rig copies.
    let source = ctx.project.clone();
    if !source.join("shells").is_dir() {
        return ctx.die(format!(
            "{} does not look like the pleamar tree (no shells/); set PLEAMAR_ROOT",
            source.display()
        ));
    }
    let pleamar = resolve(ctx, "pleamar", "PLEAMAR_BIN")?;
    let wm = resolve(ctx, "pleamar-wm", "PLEAMAR_WM_BIN")?;

    if rig.root.exists() {
        fs::remove_dir_all(&rig.root)
            .map_err(|error| Halt::Fail(format!("cannot clear {}: {error}", rig.root.display())))?;
    }
    rig.create()
        .map_err(|error| Halt::Fail(format!("cannot create the rig: {error}")))?;
    let copied = copy_tree(&source, &rig.shell())
        .map_err(|error| Halt::Fail(format!("cannot copy the shell: {error}")))?;

    let scene_file = rig.shell_scene(&options.scene);
    if !scene_file.is_file() {
        return ctx.die(format!(
            "no scene '{}' (wanted {})",
            options.scene,
            scene_file.display()
        ));
    }
    let autostart = format!("{} --scene {} --no-hud\n", pleamar, scene_file.display());
    fs::write(rig.autostart(), autostart)
        .map_err(|error| Halt::Fail(format!("cannot write the autostart: {error}")))?;

    let log = fs::File::create(rig.log())
        .map_err(|error| Halt::Fail(format!("cannot write {}: {error}", rig.log().display())))?;
    let log_err = log
        .try_clone()
        .map_err(|error| Halt::Fail(format!("cannot clone the log handle: {error}")))?;

    // Its own session, so `stop` reaches everything the compositor started.
    let mut command = Command::new("setsid");
    command
        .arg(&wm)
        .arg("headless")
        .arg("--seconds")
        .arg(options.seconds.to_string())
        .env("PLEAMAR_WM_AUTOSTART", rig.autostart())
        .stdout(Stdio::from(log))
        .stderr(Stdio::from(log_err));
    if let Some(png) = &options.png {
        command.env("PLEAMAR_HEADLESS_PNG", png);
    }
    if let Some(at) = &options.at {
        command.env("PLEAMAR_HEADLESS_AT", at);
    }
    match &options.input {
        Some(spec) => {
            command.env("PLEAMAR_HEADLESS_INPUT", spec);
        }
        None => {
            if let Ok(spec) = env::var("PLEAMAR_HEADLESS_INPUT") {
                command.env("PLEAMAR_HEADLESS_INPUT", spec);
            }
        }
    }
    apply_env(&mut command, rig);

    let child = command
        .spawn()
        .map_err(|error| Halt::Fail(format!("cannot start {wm}: {error}")))?;
    let pid = child.id();
    // Left running on purpose: the rig outlives this command (the same reason a
    // shell background job does), and `stop` is what ends it.
    drop(child);
    fs::write(rig.pid_file(), format!("{pid}\n"))
        .map_err(|error| Halt::Fail(format!("cannot write the pid file: {error}")))?;

    ctx.say(format!(
        "the rig is up (pid {pid}): {} scene(s) copied from {}, scene '{}'",
        copied,
        source.display(),
        options.scene
    ));
    ctx.say(format!(
        "  say: pleamar-rig say {} describe   log: pleamar-rig log   stop: pleamar-rig stop",
        options.scene
    ));
    ctx.say(format!("  its log: {}", rig.log().display()));
    Ok(0)
}

fn sync(ctx: &mut Ctx, rig: &Rig) -> Result<i32, Halt> {
    if running(rig).is_none() {
        return ctx.fail("the rig is not running (pleamar-rig start first)");
    }
    let source = ctx.project.clone();
    let copied = copy_tree(&source, &rig.shell())
        .map_err(|error| Halt::Fail(format!("cannot copy the shell: {error}")))?;
    ctx.say(format!("synced {copied} file(s) into the rig"));
    Ok(0)
}

fn say(ctx: &mut Ctx, rig: &Rig, options: &Options) -> Result<i32, Halt> {
    if running(rig).is_none() {
        return ctx.fail("the rig is not running (pleamar-rig start first)");
    }
    if options.rest.is_empty() {
        return ctx.die("say needs a scene and a command (pleamar-rig say bar describe)");
    }
    let pleamar = resolve(ctx, "pleamar", "PLEAMAR_BIN")?;
    let mut command = Command::new(&pleamar);
    command.arg("--say").args(&options.rest);
    apply_env(&mut command, rig);
    let status = command
        .status()
        .map_err(|error| Halt::Fail(format!("cannot run {pleamar}: {error}")))?;
    Ok(status.code().unwrap_or(1))
}

fn log(ctx: &mut Ctx, rig: &Rig, count: usize) -> Result<i32, Halt> {
    match tail_lines(&rig.log(), count) {
        Ok(lines) => {
            let mut out = std::io::stdout().lock();
            for line in lines {
                let _ = writeln!(out, "{line}");
            }
            Ok(0)
        }
        Err(error) => ctx.die(format!("cannot read {}: {error}", rig.log().display())),
    }
}

fn stop(ctx: &mut Ctx, rig: &Rig) -> Result<i32, Halt> {
    if let Some(pid) = read_pid(rig) {
        if proc::proc_exists(pid) {
            // The WM runs in a session of its own (`setsid` at start), so the
            // group TERM reaches the helper programs it started too.
            proc::kill("-TERM", pid, true);
            for _ in 0..50 {
                if !proc::proc_exists(pid) {
                    break;
                }
                proc::sleep("0.1");
            }
            if proc::proc_exists(pid) {
                proc::kill("-KILL", pid, true);
            }
        }
        let _ = fs::remove_file(rig.pid_file());
    }
    if rig.root.exists() {
        fs::remove_dir_all(&rig.root).map_err(|error| {
            Halt::Fail(format!("cannot remove {}: {error}", rig.root.display()))
        })?;
    }
    ctx.say("the rig is down and its copy removed");
    Ok(0)
}
