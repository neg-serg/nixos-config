//! nixbuild-status — one-line (or one-line-per-build) status of running Nix builds.
//!
//! It looks for live build processes in /proc and groups them into *sessions*:
//! `nixos-rebuild`, `nh os switch`, `nix build`, `nix-build`, `nix-store
//! --realise` and the activation helper. A session is the topmost matching
//! process, so the `nix build` that `nixos-rebuild` runs internally is part of
//! the rebuild, not a second entry.
//!
//! What is compiling right now is read from the Nix derivation log directory.
//! With a single session its fresh logs are attached to it; with several
//! sessions the derivations are reported as one shared list, because the logs
//! do not say which client started which build.
//!
//! Design constraints, in order:
//!   * no `nix` subprocess, no network, no sqlite — /proc and log file stats only;
//!   * no crate dependencies (the binary stays small and the build stays fast);
//!   * a panel can call it every second without noticing.
//!
//! Environment hooks (paths only, used by tests and for non-standard layouts):
//!   NBS_PROC_ROOT    default /proc
//!   NBS_LOG_ROOT     default /nix/var/log/nix/drvs
//!   NBS_STATE        default $XDG_RUNTIME_DIR/nixbuild-status.state
//!   NBS_SYSTEM_LINK  default /nix/var/nix/profiles/system

use std::collections::{HashMap, HashSet};
use std::env;
use std::fs;
use std::io::{self, Write};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::process;
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const VERSION: &str = env!("CARGO_PKG_VERSION");

/// /proc stat times tick at USER_HZ; 100 is the Linux default and what every
/// NixOS kernel ships.
const CLK_TCK: u64 = 100;

/// A derivation log written within this many seconds counts as "active now".
const DISCOVER_FRESH_SECS: u64 = 30;

/// Remembered derivations are kept this long while a build process is alive:
/// a long compile can run for minutes without emitting a single log line.
const REMEMBER_TTL_SECS: i64 = 900;

const STATE_MAX: usize = 16;

/// How many concurrent sessions are reported (oldest first).
const SESSIONS_MAX: usize = 8;

/// Upper bound for one full log-directory walk (cold start fallback).
const SCAN_ENTRY_CAP: usize = 200_000;

const HELP: &str = "\
nixbuild-status — status of running Nix builds for status bars

Usage: nixbuild-status [OPTIONS]

Options:
  -f, --format <FMT>   plain | ansi | waybar | i3bar | json | polybar | list
                       [default: plain]
      --json           shorthand for --format waybar
      --list           shorthand for --format list: one line per build
  -i, --icons <SET>    nerd | plain | none                            [default: nerd]
      --no-color       disable ANSI color codes
  -c, --compact        drop the state word when the icon already shows it
      --hide-idle      print an empty line instead of the idle line
  -w, --watch [SECS]   stay resident and print only on change (default: 1s)
  -h, --help           print this help
  -V, --version        print the version

Formats: `list` prints one line per build (`kind target · derivation · time`)
and nothing while no build is running.
";

// ---------------------------------------------------------------------------
// state model
// ---------------------------------------------------------------------------

/// Overall state of the machine (also the phase of a single session).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Kind {
    Idle,
    Evaluating,
    Building,
    Activating,
}

impl Kind {
    fn word(self) -> &'static str {
        match self {
            Kind::Idle => "idle",
            Kind::Evaluating => "evaluating",
            Kind::Building => "building",
            Kind::Activating => "activating",
        }
    }

    fn short(self) -> &'static str {
        match self {
            Kind::Idle => "idle",
            Kind::Evaluating => "eval",
            Kind::Building => "build",
            Kind::Activating => "switch",
        }
    }

    /// Catppuccin Mocha tones, matching the rest of the desktop theming.
    fn hex(self) -> &'static str {
        match self {
            Kind::Idle => "#6c7086",       // overlay0
            Kind::Evaluating => "#89b4fa", // blue
            Kind::Building => "#f9e2af",   // yellow
            Kind::Activating => "#89dceb", // sky
        }
    }

    fn ansi(self) -> &'static str {
        match self {
            Kind::Idle => "\x1b[38;2;108;112;134m",
            Kind::Evaluating => "\x1b[38;2;137;180;250m",
            Kind::Building => "\x1b[38;2;249;226;175m",
            Kind::Activating => "\x1b[38;2;137;220;235m",
        }
    }
}

/// Which program family a session belongs to.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Family {
    NixosRebuild,
    Nh,
    Nix,
    NixBuild,
    NixStore,
    Activate,
}

impl Family {
    fn name(self) -> &'static str {
        match self {
            Family::NixosRebuild => "nixos-rebuild",
            Family::Nh => "nh",
            Family::Nix => "nix",
            Family::NixBuild => "nix-build",
            Family::NixStore => "nix-store",
            Family::Activate => "switch-to-configuration",
        }
    }

    /// Best-effort command line for the tooltip.
    fn command(self) -> &'static str {
        match self {
            Family::NixosRebuild => "nixos-rebuild",
            Family::Nh => "nh",
            Family::Nix => "nix build",
            Family::NixBuild => "nix-build",
            Family::NixStore => "nix-store --realise",
            Family::Activate => "switch-to-configuration",
        }
    }
}

#[derive(Clone, Debug)]
struct Session {
    family: Family,
    /// switch | boot | test | build | ... (nixos-rebuild / nh).
    action: Option<String>,
    /// Flake host the build targets, when it can be read from the command line.
    host: Option<String>,
    /// Flake ref, attribute, .nix file or package the build targets.
    target: Option<String>,
    cwd: Option<String>,
    elapsed: u64,
    phase: Kind,
    /// Fresh derivations; filled in only when the session can be told apart.
    drvs: Vec<String>,
    pid: u32,
}

impl Session {
    /// `nixos-rebuild switch trantor`, `nix build .#default`, … — the one-line
    /// identity used by the tooltip blocks and the `list` format.
    fn head(&self) -> String {
        let mut parts = vec![self.family.name().to_string()];
        if let Some(action) = &self.action {
            parts.push(action.clone());
        }
        if let Some(host) = &self.host {
            parts.push(host.clone());
        } else if let Some(target) = &self.target {
            parts.push(target.clone());
        } else if let Some(cwd) = &self.cwd {
            parts.push(cwd.clone());
        }
        parts.join(" ")
    }

    fn header(&self) -> &'static str {
        match self.family {
            Family::NixosRebuild | Family::Nh | Family::Activate => "NixOS build",
            Family::Nix | Family::NixBuild | Family::NixStore => "Nix build",
        }
    }
}

#[derive(Clone, Debug)]
struct Status {
    kind: Kind,
    /// Elapsed time of the oldest session (the whole operation).
    elapsed: Option<u64>,
    /// Fresh derivations, freshest first (shared across sessions).
    drvs: Vec<String>,
    /// Active build sessions, oldest first.
    sessions: Vec<Session>,
    generation: Option<u64>,
}

impl Status {
    fn idle(generation: Option<u64>) -> Status {
        Status {
            kind: Kind::Idle,
            elapsed: None,
            drvs: Vec::new(),
            sessions: Vec::new(),
            generation,
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Format {
    Plain,
    Ansi,
    Waybar,
    I3bar,
    Polybar,
    /// One line per session; no output while idle.
    List,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Icons {
    Nerd,
    Plain,
    None,
}

impl Icons {
    fn glyph(self, kind: Kind) -> Option<&'static str> {
        match self {
            Icons::Nerd => Some(match kind {
                Kind::Idle => "\u{2744}",       // snowflake (safe in any font)
                Kind::Evaluating => "\u{f002}", // nf-fa-search
                Kind::Building => "\u{f013}",   // nf-fa-gear
                Kind::Activating => "\u{f0e7}", // nf-fa-bolt
            }),
            Icons::Plain => Some(match kind {
                Kind::Idle => "\u{2744}",
                Kind::Evaluating => "\u{2026}",
                Kind::Building => "\u{2699}",
                Kind::Activating => "\u{26a1}",
            }),
            Icons::None => None,
        }
    }
}

#[derive(Clone, Copy)]
struct Opts {
    format: Format,
    icons: Icons,
    compact: bool,
    hide_idle: bool,
    no_color: bool,
    watch: Option<Duration>,
    help: bool,
    version: bool,
}

/// Filesystem roots; every one of them is overridable so tests can build a
/// synthetic /proc and log tree.
#[derive(Clone)]
struct Paths {
    proc_root: PathBuf,
    log_root: PathBuf,
    state: PathBuf,
    system_link: PathBuf,
}

impl Paths {
    fn from_env() -> Paths {
        let state = env::var_os("NBS_STATE")
            .map(PathBuf::from)
            .or_else(|| {
                env::var_os("XDG_RUNTIME_DIR")
                    .map(|d| PathBuf::from(d).join("nixbuild-status.state"))
            })
            .unwrap_or_else(|| {
                let uid = fs::metadata("/proc/self").map(|m| m.uid()).unwrap_or(0);
                PathBuf::from(format!("/tmp/nixbuild-status-{uid}.state"))
            });
        Paths {
            proc_root: env_path("NBS_PROC_ROOT", "/proc"),
            log_root: env_path("NBS_LOG_ROOT", "/nix/var/log/nix/drvs"),
            state,
            system_link: env_path("NBS_SYSTEM_LINK", "/nix/var/nix/profiles/system"),
        }
    }
}

fn env_path(var: &str, default: &str) -> PathBuf {
    env::var_os(var)
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(default))
}

// ---------------------------------------------------------------------------
// /proc scanning
// ---------------------------------------------------------------------------

struct Proc {
    pid: u32,
    ppid: u32,
    kind: Family,
    elapsed: u64,
    argv: Vec<String>,
    cwd: Option<String>,
}

fn scan_procs(root: &Path) -> Vec<Proc> {
    let uptime = read_uptime(root);
    let mut out = Vec::new();
    let entries = match fs::read_dir(root) {
        Ok(e) => e,
        Err(_) => return out,
    };
    for entry in entries.flatten() {
        let name = entry.file_name();
        let Some(pid) = name.to_str().and_then(|s| s.parse::<u32>().ok()) else {
            continue;
        };
        let dir = entry.path();
        let Ok(cmdline) = fs::read(dir.join("cmdline")) else {
            continue;
        };
        let argv = split_cmdline(&cmdline);
        let Some(kind) = classify(&argv) else {
            continue;
        };
        let Ok(stat) = fs::read_to_string(dir.join("stat")) else {
            continue;
        };
        let Some((ppid, ticks)) = parse_stat(&stat) else {
            continue;
        };
        let started = ticks as f64 / CLK_TCK as f64;
        let elapsed = if started >= uptime {
            0
        } else {
            (uptime - started) as u64
        };
        let cwd = fs::read_link(dir.join("cwd"))
            .ok()
            .and_then(|p| p.to_str().map(str::to_string));
        out.push(Proc {
            pid,
            ppid,
            kind,
            elapsed,
            argv,
            cwd,
        });
    }
    out
}

/// Process classification. Shebang scripts (nixos-rebuild, nix-build,
/// switch-to-configuration) run as `interpreter script args...`, so argv[1]
/// counts as a program name — but only when it is a path, otherwise
/// `rg nixos-rebuild` would look like a rebuild.
fn classify(argv: &[String]) -> Option<Family> {
    let head0 = argv.first().map(|a| basename(a));
    let head1 = argv.get(1).filter(|a| a.contains('/')).map(|a| basename(a));
    let matches = |name: &str| head0 == Some(name) || head1 == Some(name);
    let is_nix_build = |b: &str| b == "nix-build" || b.starts_with("nix-build-");

    if matches("nixos-rebuild") {
        return Some(Family::NixosRebuild);
    }
    if matches("switch-to-configuration") || matches("switch-to-configuration-ng") {
        return Some(Family::Activate);
    }
    if matches("nh") {
        return Some(Family::Nh);
    }
    if head0.is_some_and(is_nix_build) || head1.is_some_and(is_nix_build) {
        return Some(Family::NixBuild);
    }
    if matches("nix-store")
        && argv
            .iter()
            .any(|a| a == "--realise" || a == "--realize" || a == "-r")
    {
        return Some(Family::NixStore);
    }
    if head0 == Some("nix") && argv.iter().skip(1).any(|a| a == "build") {
        return Some(Family::Nix);
    }
    None
}

fn basename(p: &str) -> &str {
    p.rsplit('/').next().unwrap_or(p)
}

fn split_cmdline(bytes: &[u8]) -> Vec<String> {
    bytes
        .split(|b| *b == 0)
        .filter(|s| !s.is_empty())
        .map(|s| String::from_utf8_lossy(s).into_owned())
        .collect()
}

fn read_uptime(root: &Path) -> f64 {
    fs::read_to_string(root.join("uptime"))
        .ok()
        .and_then(|s| {
            s.split_whitespace()
                .next()
                .and_then(|t| t.parse::<f64>().ok())
        })
        .unwrap_or(0.0)
}

/// ppid is field 4 and starttime is field 22 of /proc/<pid>/stat. The comm
/// field (field 2) is parenthesized and may contain spaces or parentheses, so
/// parsing restarts after the last ')'.
fn parse_stat(stat: &str) -> Option<(u32, u64)> {
    let close = stat.rfind(')')?;
    let rest: Vec<&str> = stat[close + 1..].split_ascii_whitespace().collect();
    let ppid = rest.get(1)?.parse().ok()?;
    let starttime = rest.get(19)?.parse().ok()?;
    Some((ppid, starttime))
}

// ---------------------------------------------------------------------------
// sessions
// ---------------------------------------------------------------------------

/// Group the matched processes into sessions: the topmost matching ancestor
/// wins, so `nixos-rebuild` and the `nix build` it runs stay one session.
fn build_sessions(procs: &[Proc]) -> Vec<Session> {
    let parent: HashMap<u32, u32> = procs.iter().map(|p| (p.pid, p.ppid)).collect();
    let by_pid: HashMap<u32, &Proc> = procs.iter().map(|p| (p.pid, p)).collect();

    let mut groups: Vec<(u32, Vec<&Proc>)> = Vec::new();
    for proc in procs {
        let root = climb_root(proc.pid, &parent);
        match groups.iter_mut().find(|(pid, _)| *pid == root) {
            Some((_, members)) => members.push(proc),
            None => groups.push((root, vec![proc])),
        }
    }

    let mut sessions: Vec<Session> = groups
        .into_iter()
        .filter_map(|(root, members)| {
            let head = by_pid.get(&root)?;
            let activating = members.iter().any(|m| m.kind == Family::Activate);
            let phase = if activating {
                Kind::Activating
            } else {
                Kind::Evaluating
            };
            Some(Session {
                family: head.kind,
                action: session_action(&head.argv),
                host: session_host(&head.argv),
                target: target_arg(&head.argv),
                cwd: head.cwd.clone(),
                elapsed: head.elapsed,
                phase,
                drvs: Vec::new(),
                pid: head.pid,
            })
        })
        .collect();

    // Oldest first: the session that has been running longest is the one the
    // user is most likely waiting for.
    sessions.sort_by(|a, b| b.elapsed.cmp(&a.elapsed).then(a.pid.cmp(&b.pid)));
    sessions.truncate(SESSIONS_MAX);
    sessions
}

fn climb_root(pid: u32, parent: &HashMap<u32, u32>) -> u32 {
    let mut root = pid;
    let mut cur = pid;
    for _ in 0..32 {
        let Some(&ppid) = parent.get(&cur) else {
            break;
        };
        // Only matched processes chain together; a shell or systemd above the
        // build must not swallow the session, or the group loses its head.
        if ppid == 0 || ppid == cur || !parent.contains_key(&ppid) {
            break;
        }
        root = ppid;
        cur = ppid;
    }
    root
}

const REBUILD_ACTIONS: [&str; 8] = [
    "switch",
    "boot",
    "test",
    "build",
    "dry-build",
    "dry-activate",
    "repl",
    "edit",
];

fn session_action(argv: &[String]) -> Option<String> {
    argv.iter()
        .skip(1)
        .find(|a| REBUILD_ACTIONS.contains(&a.as_str()))
        .cloned()
}

fn session_host(argv: &[String]) -> Option<String> {
    if let Some(flake) = flag_value(argv, "--flake") {
        if let Some(host) = flake_host(flake) {
            return Some(host);
        }
    }
    argv.iter()
        .find_map(|a| attr_host(a).or_else(|| flake_host(a)))
}

/// Best-effort build target: the flake reference, attribute, .nix file or
/// source the command line names. Flag values are skipped so `--option
/// substitute false` cannot masquerade as a target.
fn target_arg(argv: &[String]) -> Option<String> {
    if let Some(flake) = flag_value(argv, "--flake") {
        return Some(flake.to_string());
    }
    if let Some(file) = flag_value(argv, "-f").or_else(|| flag_value(argv, "--file")) {
        return Some(file.to_string());
    }
    if let Some(attr) = flag_value(argv, "-A").or_else(|| flag_value(argv, "--attr")) {
        return Some(attr.to_string());
    }
    let mut skip_next = false;
    for (i, arg) in argv.iter().enumerate() {
        if i == 0 {
            continue;
        }
        if skip_next {
            skip_next = false;
            continue;
        }
        if TARGET_FLAGS_WITH_VALUE.contains(&arg.as_str()) {
            skip_next = true;
            continue;
        }
        if arg.starts_with('-') {
            continue;
        }
        if REBUILD_ACTIONS.contains(&arg.as_str()) || NH_SUBCOMMANDS.contains(&arg.as_str()) {
            continue;
        }
        if arg.contains('#') || arg.ends_with(".nix") || arg.starts_with('.') || arg.contains('/') {
            return Some(arg.clone());
        }
    }
    None
}

const NH_SUBCOMMANDS: [&str; 6] = ["os", "home", "darwin", "search", "repl", "clean"];

const TARGET_FLAGS_WITH_VALUE: [&str; 14] = [
    "--option",
    "--arg",
    "--argstr",
    "--include",
    "-I",
    "--out-link",
    "-o",
    "--profile",
    "--builders",
    "--max-jobs",
    "-j",
    "--cores",
    "--log-format",
    "--print-build-logs",
];

fn flag_value<'a>(argv: &'a [String], flag: &str) -> Option<&'a str> {
    let eq = format!("{flag}=");
    for (i, arg) in argv.iter().enumerate() {
        if arg == flag {
            return argv.get(i + 1).map(|s| s.as_str());
        }
        if let Some(v) = arg.strip_prefix(&eq) {
            return Some(v);
        }
    }
    None
}

/// `--flake /etc/nixos#trantor` -> `trantor`.
fn flake_host(value: &str) -> Option<String> {
    let (_, fragment) = value.split_once('#')?;
    let fragment = fragment.split(':').next().unwrap_or(fragment);
    if fragment.is_empty() {
        None
    } else {
        Some(fragment.to_string())
    }
}

/// `.#nixosConfigurations.trantor.config.system.build.toplevel` -> `trantor`.
fn attr_host(arg: &str) -> Option<String> {
    const MARK: &str = "nixosConfigurations.";
    let rest = &arg[arg.find(MARK)? + MARK.len()..];
    let host: String = rest
        .chars()
        .take_while(|c| *c != '.' && *c != ':' && *c != '/' && *c != '#')
        .collect();
    if host.is_empty() {
        None
    } else {
        Some(host.to_string())
    }
}

// ---------------------------------------------------------------------------
// derivation log scanning
// ---------------------------------------------------------------------------

struct Drv {
    path: PathBuf,
    mtime: i64,
    name: String,
}

fn unix_now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// Names of the derivations whose logs are being written right now.
///
/// Cost model: one pass over the 256 log subdirectories (directory mtimes
/// only) plus a stat per remembered file. A full walk of the log directory
/// happens only once per build, on a cold start, and its result is cached in a
/// small state file so the next one-shot run does not repeat it.
fn active_drvs(log_root: &Path, state_path: &Path, fresh: u64) -> Vec<String> {
    let now = unix_now();
    let fresh = fresh as i64;
    let mut found: Vec<Drv> = Vec::new();
    let mut seen: HashSet<PathBuf> = HashSet::new();

    for path in load_state(state_path) {
        if let Some(drv) = drv_at(&path) {
            if now - drv.mtime <= REMEMBER_TTL_SECS && seen.insert(drv.path.clone()) {
                found.push(drv);
            }
        }
    }
    let remembered = found.len();

    if !found.iter().any(|d| now - d.mtime <= fresh) {
        // Recently touched directories can only contain freshly created logs.
        scan_logs(log_root, now, fresh, false, &mut seen, &mut found);
        if found.is_empty() {
            // Cold start in the middle of a build: pay for the full walk once.
            // The window is the remembered TTL, not `fresh`: a compile can run
            // quietly for minutes, and the newest log found this way is still
            // the best available guess for "what is building right now".
            scan_logs(
                log_root,
                now,
                REMEMBER_TTL_SECS,
                true,
                &mut seen,
                &mut found,
            );
        }
    }

    if env::var_os("NBS_DEBUG").is_some() {
        eprintln!(
            "nbs-debug: remembered={} found={} newest={:?}",
            remembered,
            found.len(),
            found
                .iter()
                .max_by_key(|d| d.mtime)
                .map(|d| (d.name.as_str(), now - d.mtime))
        );
    }

    found.sort_by(|a, b| b.mtime.cmp(&a.mtime).then_with(|| a.name.cmp(&b.name)));
    found.truncate(STATE_MAX);
    save_state(
        state_path,
        &found.iter().map(|d| d.path.clone()).collect::<Vec<_>>(),
    );

    // What the caller displays: the logs being written right now, freshest
    // first. When none is fresh (a compile can be quiet for minutes), fall
    // back to the newest known derivation — one name, not a stale list, so the
    // "+N parallel" counter keeps meaning "several builds are running".
    let mut shown: Vec<&Drv> = found.iter().filter(|d| now - d.mtime <= fresh).collect();
    if shown.is_empty() {
        if let Some(newest) = found.iter().max_by_key(|d| d.mtime) {
            shown.push(newest);
        }
    }
    shown.into_iter().map(|d| d.name.clone()).collect()
}

fn scan_logs(
    root: &Path,
    now: i64,
    fresh: i64,
    all: bool,
    seen: &mut HashSet<PathBuf>,
    out: &mut Vec<Drv>,
) {
    let mut budget = SCAN_ENTRY_CAP;
    let mut dirs_seen = 0usize;
    let mut dirs_scanned = 0usize;
    let mut dirs_failed = 0usize;
    let mut fresh_files = 0usize;
    let Ok(dirs) = fs::read_dir(root) else {
        return;
    };
    for dir in dirs.flatten() {
        let dir_path = dir.path();
        let Ok(meta) = dir.metadata() else {
            dirs_failed += 1;
            continue;
        };
        if !meta.is_dir() {
            continue;
        }
        dirs_seen += 1;
        if !all && now - meta.mtime() > fresh {
            // No file was created here recently, so nothing new is building.
            continue;
        }
        dirs_scanned += 1;
        let Ok(files) = fs::read_dir(&dir_path) else {
            continue;
        };
        for file in files.flatten() {
            budget = budget.saturating_sub(1);
            if budget == 0 {
                return;
            }
            let path = file.path();
            let Some(name) = path.file_name().and_then(|n| n.to_str()).and_then(drv_name) else {
                continue;
            };
            let Ok(meta) = file.metadata() else {
                continue;
            };
            let mtime = meta.mtime();
            if now - mtime > fresh || !seen.insert(path.clone()) {
                continue;
            }
            fresh_files += 1;
            out.push(Drv { path, mtime, name });
        }
    }
    if env::var_os("NBS_DEBUG").is_some() {
        eprintln!(
            "nbs-debug: scan all={all} dirs={dirs_scanned}/{dirs_seen} failed={dirs_failed} fresh_files={fresh_files} window={fresh}s"
        );
    }
}

fn drv_at(path: &Path) -> Option<Drv> {
    let meta = fs::metadata(path).ok()?;
    if !meta.is_file() {
        return None;
    }
    let name = drv_name(path.file_name()?.to_str()?)?;
    Some(Drv {
        path: path.to_path_buf(),
        mtime: meta.mtime(),
        name,
    })
}

/// `/nix/var/log/nix/drvs/1a/<30 base32>-hello-2.12.drv.bz2` -> `hello-2.12`.
///
/// Nix store hashes are base32 (lowercase letters and digits). Log file names
/// carry only the last 30 characters of the 32-character store hash (the
/// first two are the subdirectory name); a plain store path carries all 32.
fn drv_name(file_name: &str) -> Option<String> {
    let base = file_name
        .strip_suffix(".drv.bz2")
        .or_else(|| file_name.strip_suffix(".drv"))?;
    let name = match base.split_once('-') {
        Some((hash, rest))
            if matches!(hash.len(), 30 | 32)
                && hash
                    .chars()
                    .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit()) =>
        {
            rest
        }
        _ => base,
    };
    if name.is_empty() {
        None
    } else {
        Some(name.to_string())
    }
}

fn load_state(path: &Path) -> Vec<PathBuf> {
    fs::read_to_string(path)
        .map(|body| {
            body.lines()
                .map(str::trim)
                .filter(|l| !l.is_empty())
                .map(PathBuf::from)
                .collect()
        })
        .unwrap_or_default()
}

fn save_state(path: &Path, paths: &[PathBuf]) {
    let body: String = paths.iter().map(|p| format!("{}\n", p.display())).collect();
    if fs::read_to_string(path)
        .map(|cur| cur == body)
        .unwrap_or(false)
    {
        return;
    }
    let tmp = path.with_extension("tmp");
    if fs::write(&tmp, body).is_ok() {
        let _ = fs::rename(&tmp, path);
    }
}

fn read_generation(system_link: &Path) -> Option<u64> {
    let target = fs::read_link(system_link).ok()?;
    let name = target.file_name()?.to_str()?;
    name.strip_suffix("-link")?.rsplit('-').next()?.parse().ok()
}

// ---------------------------------------------------------------------------
// status assembly
// ---------------------------------------------------------------------------

fn collect(paths: &Paths, fresh: u64) -> Status {
    let procs = scan_procs(&paths.proc_root);
    let generation = read_generation(&paths.system_link);
    let mut sessions = build_sessions(&procs);
    if sessions.is_empty() {
        return Status::idle(generation);
    }

    let drvs = active_drvs(&paths.log_root, &paths.state, fresh);
    let activating = sessions.iter().any(|s| s.phase == Kind::Activating);
    let kind = if activating {
        Kind::Activating
    } else if drvs.is_empty() {
        Kind::Evaluating
    } else {
        Kind::Building
    };

    // With one session the fresh derivations belong to it; with several there
    // is no way to tell which client started which build, so they stay shared.
    if sessions.len() == 1 {
        let session = &mut sessions[0];
        session.drvs = drvs.clone();
        if session.phase != Kind::Activating {
            session.phase = if drvs.is_empty() {
                Kind::Evaluating
            } else {
                Kind::Building
            };
        }
    }

    let elapsed = sessions.iter().map(|s| s.elapsed).max();
    Status {
        kind,
        elapsed,
        drvs,
        sessions,
        generation,
    }
}

// ---------------------------------------------------------------------------
// rendering
// ---------------------------------------------------------------------------

fn fmt_elapsed(secs: u64) -> String {
    if secs < 60 {
        format!("{secs}s")
    } else if secs < 3600 {
        format!("{}:{:02}", secs / 60, secs % 60)
    } else {
        format!("{}:{:02}:{:02}", secs / 3600, (secs % 3600) / 60, secs % 60)
    }
}

fn build_text(s: &Status, o: &Opts) -> String {
    let icon = o.icons.glyph(s.kind);
    let mut parts: Vec<String> = Vec::new();
    if let Some(glyph) = icon {
        parts.push(glyph.to_string());
    }

    // Several builds: the sentence is a count plus what is compiling now.
    if s.sessions.len() > 1 {
        let mut detail = format!("{} builds", s.sessions.len());
        if let Some(drv) = s.drvs.first() {
            detail.push_str(&format!(" · {drv}"));
            if s.drvs.len() > 1 {
                detail.push_str(&format!(" +{}", s.drvs.len() - 1));
            }
        }
        parts.push(detail);
        if let Some(secs) = s.elapsed {
            parts.push(fmt_elapsed(secs));
        }
        return parts.join(" ");
    }

    let mut detail = String::new();
    match s.kind {
        Kind::Idle => {
            if let Some(gen) = s.generation {
                detail = format!("gen {gen}");
            }
        }
        _ => {
            detail = match s.kind {
                Kind::Building => {
                    let mut drv = s.drvs.first().cloned().unwrap_or_default();
                    if s.drvs.len() > 1 {
                        drv.push_str(&format!(" +{}", s.drvs.len() - 1));
                    }
                    drv
                }
                _ => s
                    .sessions
                    .first()
                    .and_then(|x| x.host.clone().or_else(|| x.target.clone()))
                    .unwrap_or_default(),
            };
        }
    }

    let drop_verb = o.compact && icon.is_some() && !detail.is_empty() && s.kind != Kind::Idle;
    if !drop_verb {
        parts.push(
            if o.compact {
                s.kind.short()
            } else {
                s.kind.word()
            }
            .to_string(),
        );
    }
    if !detail.is_empty() {
        parts.push(detail);
    }
    if let Some(secs) = s.elapsed {
        parts.push(fmt_elapsed(secs));
    }
    parts.join(" ")
}

fn tooltip(s: &Status) -> String {
    let mut lines: Vec<String> = Vec::new();

    if s.sessions.len() > 1 {
        lines.push(format!("Nix builds: {}", s.sessions.len()));
        for session in &s.sessions {
            lines.push(format!(
                "• {} ({})",
                session.head(),
                fmt_elapsed(session.elapsed)
            ));
            if !session.drvs.is_empty() {
                lines.push(format!("  derivation: {}", session.drvs.join(", ")));
            }
        }
        if s.sessions.iter().all(|x| x.drvs.is_empty()) && !s.drvs.is_empty() {
            lines.push(format!("active derivations: {}", s.drvs.join(", ")));
        }
    } else if let Some(session) = s.sessions.first() {
        lines.push(session.header().to_string());
        lines.push(format!("command: {}", session.family.command()));
        lines.push(format!("state: {}", session.phase.word()));
        if let Some(action) = &session.action {
            lines.push(format!("action: {action}"));
        }
        if let Some(host) = &session.host {
            lines.push(format!("host: {host}"));
        }
        if let Some(target) = &session.target {
            lines.push(format!("target: {target}"));
        }
        if !s.drvs.is_empty() {
            lines.push(format!("derivation: {}", s.drvs[0]));
            if s.drvs.len() > 1 {
                lines.push(format!("parallel: {}", s.drvs.len()));
            }
        }
        if let Some(cwd) = &session.cwd {
            lines.push(format!("cwd: {cwd}"));
        }
        lines.push(format!("elapsed: {}", fmt_elapsed(session.elapsed)));
    } else {
        lines.push("NixOS build".to_string());
        lines.push("state: idle".to_string());
    }

    if let Some(gen) = s.generation {
        lines.push(format!("generation: {gen}"));
    }
    lines.join("\n")
}

/// One line per session for the `list` format.
fn list_text(s: &Status) -> String {
    s.sessions
        .iter()
        .map(|session| {
            let mut line = session.head();
            if !session.drvs.is_empty() {
                line.push_str(&format!(" · {}", session.drvs.join(", ")));
            }
            line.push_str(&format!(" · {}", fmt_elapsed(session.elapsed)));
            line
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn session_json(session: &Session) -> String {
    let mut fields: Vec<String> = vec![
        format!("\"head\":\"{}\"", json_escape(&session.head())),
        format!("\"family\":\"{}\"", json_escape(session.family.name())),
        format!("\"phase\":\"{}\"", session.phase.word()),
        format!("\"elapsed\":{}", session.elapsed),
        format!("\"elapsed_text\":\"{}\"", fmt_elapsed(session.elapsed)),
        format!("\"pid\":{}", session.pid),
    ];
    if let Some(action) = &session.action {
        fields.push(format!("\"action\":\"{}\"", json_escape(action)));
    }
    if let Some(host) = &session.host {
        fields.push(format!("\"host\":\"{}\"", json_escape(host)));
    }
    if let Some(target) = &session.target {
        fields.push(format!("\"target\":\"{}\"", json_escape(target)));
    }
    if let Some(cwd) = &session.cwd {
        fields.push(format!("\"cwd\":\"{}\"", json_escape(cwd)));
    }
    if !session.drvs.is_empty() {
        fields.push(format!("\"drvs\":[{}]", json_list(&session.drvs)));
    }
    format!("{{{}}}", fields.join(","))
}

fn json_list(items: &[String]) -> String {
    items
        .iter()
        .map(|item| format!("\"{}\"", json_escape(item)))
        .collect::<Vec<_>>()
        .join(",")
}

fn render(s: &Status, o: &Opts) -> String {
    let text = build_text(s, o);
    match o.format {
        Format::Plain => text,
        Format::List => list_text(s),
        Format::Ansi => {
            if o.no_color {
                text
            } else {
                format!("{}{}\x1b[0m", s.kind.ansi(), text)
            }
        }
        Format::Polybar => format!("%{{F{}}}{}%{{F-}}", s.kind.hex(), poly_escape(&text)),
        Format::Waybar => {
            let builds = s
                .sessions
                .iter()
                .map(session_json)
                .collect::<Vec<_>>()
                .join(",");
            format!(
                "{{\"text\":\"{}\",\"alt\":\"{}\",\"class\":\"{}\",\"tooltip\":\"{}\",\"count\":{},\"builds\":[{}],\"drvs\":[{}]}}",
                json_escape(&text),
                s.kind.word(),
                s.kind.word(),
                json_escape(&tooltip(s)),
                s.sessions.len(),
                builds,
                json_list(&s.drvs)
            )
        }
        Format::I3bar => {
            let builds = s
                .sessions
                .iter()
                .map(session_json)
                .collect::<Vec<_>>()
                .join(",");
            format!(
                "{{\"name\":\"nixbuild\",\"full_text\":\"{}\",\"color\":\"{}\",\"tooltip\":\"{}\",\"count\":{},\"builds\":[{}],\"drvs\":[{}]}}",
                json_escape(&text),
                s.kind.hex(),
                json_escape(&tooltip(s)),
                s.sessions.len(),
                builds,
                json_list(&s.drvs)
            )
        }
    }
}

fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

/// Polybar reads `%{...}` as markup, so a literal percent must be doubled.
fn poly_escape(s: &str) -> String {
    s.replace('%', "%%")
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

fn parse_format(value: &str) -> Result<Format, String> {
    match value {
        "plain" => Ok(Format::Plain),
        "ansi" | "color" | "colour" => Ok(Format::Ansi),
        "waybar" | "json" => Ok(Format::Waybar),
        "i3bar" => Ok(Format::I3bar),
        "polybar" => Ok(Format::Polybar),
        "list" | "lines" => Ok(Format::List),
        other => Err(format!("unknown format: {other}")),
    }
}

fn parse_icons(value: &str) -> Result<Icons, String> {
    match value {
        "nerd" | "nerdfont" => Ok(Icons::Nerd),
        "plain" | "unicode" => Ok(Icons::Plain),
        "none" | "no" | "off" => Ok(Icons::None),
        other => Err(format!("unknown icon set: {other}")),
    }
}

fn parse_args(args: Vec<String>) -> Result<Opts, String> {
    let mut o = Opts {
        format: Format::Plain,
        icons: Icons::Nerd,
        compact: false,
        hide_idle: false,
        no_color: false,
        watch: None,
        help: false,
        version: false,
    };
    let mut i = 0;
    while i < args.len() {
        let arg = args[i].as_str();
        match arg {
            "-h" | "--help" => o.help = true,
            "-V" | "--version" => o.version = true,
            "-c" | "--compact" => o.compact = true,
            "--hide-idle" => o.hide_idle = true,
            "--no-color" => o.no_color = true,
            "--json" => o.format = Format::Waybar,
            "--list" => o.format = Format::List,
            "-f" | "--format" => {
                i += 1;
                o.format = parse_format(args.get(i).ok_or("--format needs a value")?)?;
            }
            "-i" | "--icons" => {
                i += 1;
                o.icons = parse_icons(args.get(i).ok_or("--icons needs a value")?)?;
            }
            "-w" | "--watch" => {
                if let Some(next) = args.get(i + 1) {
                    if let Ok(secs) = next.parse::<f64>() {
                        o.watch = Some(clamp_interval(secs));
                        i += 1;
                    }
                }
                if o.watch.is_none() {
                    o.watch = Some(Duration::from_secs(1));
                }
            }
            value if value.starts_with("--format=") => {
                o.format = parse_format(&value["--format=".len()..])?;
            }
            value if value.starts_with("--icons=") => {
                o.icons = parse_icons(&value["--icons=".len()..])?;
            }
            value if value.starts_with("--watch=") => {
                let secs = value["--watch=".len()..].parse::<f64>().map_err(|_| {
                    format!("invalid --watch value: {}", &value["--watch=".len()..])
                })?;
                o.watch = Some(clamp_interval(secs));
            }
            other => return Err(format!("unknown argument: {other}")),
        }
        i += 1;
    }
    Ok(o)
}

fn clamp_interval(secs: f64) -> Duration {
    Duration::from_secs_f64(secs.max(0.1))
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

fn emit(line: &str) -> bool {
    let mut out = io::stdout();
    if writeln!(out, "{line}").is_err() {
        return false; // broken pipe: the panel went away, exit quietly
    }
    out.flush().is_ok()
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let opts = match parse_args(args) {
        Ok(o) => o,
        Err(e) => {
            eprintln!("nixbuild-status: {e}");
            eprintln!("Try 'nixbuild-status --help' for more information.");
            process::exit(2);
        }
    };
    if opts.help {
        print!("{HELP}");
        return;
    }
    if opts.version {
        println!("nixbuild-status {VERSION}");
        return;
    }

    let paths = Paths::from_env();
    let hide = |kind: Kind, line: String| -> String {
        if opts.hide_idle && kind == Kind::Idle {
            String::new()
        } else {
            line
        }
    };
    // Line-oriented output (`list`) stays silent instead of printing empty
    // lines; `--hide-idle` in the other formats keeps its empty line so a
    // panel can still clear the widget.
    let print_line = |line: &str| -> bool {
        if line.is_empty() {
            return true;
        }
        emit(line)
    };

    match opts.watch {
        None => {
            let status = collect(&paths, DISCOVER_FRESH_SECS);
            let line = hide(status.kind, render(&status, &opts));
            if !print_line(&line) {
                process::exit(0);
            }
        }
        Some(interval) => {
            let mut last: Option<String> = None;
            loop {
                let status = collect(&paths, DISCOVER_FRESH_SECS);
                let line = hide(status.kind, render(&status, &opts));
                if last.as_deref() != Some(line.as_str()) {
                    if !print_line(&line) {
                        return;
                    }
                    last = Some(line);
                }
                thread::sleep(interval);
            }
        }
    }
}

// ---------------------------------------------------------------------------
// tests
// ---------------------------------------------------------------------------
