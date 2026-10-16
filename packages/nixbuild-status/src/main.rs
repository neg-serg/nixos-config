//! nixbuild-status — one-line status of a running NixOS build.
//!
//! It looks for live `nixos-rebuild`, `nix build` / `nix-build` and
//! `switch-to-configuration` processes in /proc, names the derivation that is
//! currently being written by looking at the Nix derivation log directory, and
//! prints exactly one line in the requested format.
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

use std::collections::HashSet;
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

/// Upper bound for one full log-directory walk (cold start fallback).
const SCAN_ENTRY_CAP: usize = 200_000;

const HELP: &str = "\
nixbuild-status — one-line NixOS build status for status bars

Usage: nixbuild-status [OPTIONS]

Options:
  -f, --format <FMT>   plain | ansi | waybar | i3bar | json | polybar [default: plain]
      --json           shorthand for --format waybar
  -i, --icons <SET>    nerd | plain | none                            [default: nerd]
      --no-color       disable ANSI color codes
  -c, --compact        drop the state word when the icon already shows it
      --hide-idle      print an empty line instead of the idle line
  -w, --watch [SECS]   stay resident and print only on change (default: 1s)
  -h, --help           print this help
  -V, --version        print the version
";

// ---------------------------------------------------------------------------
// state model
// ---------------------------------------------------------------------------

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

#[derive(Clone, Debug)]
struct Status {
    kind: Kind,
    elapsed: Option<u64>,
    /// Current derivations, freshest first.
    drvs: Vec<String>,
    /// nixos-rebuild action (switch, boot, test, build, ...).
    action: Option<String>,
    /// Flake host / attribute the build targets.
    host: Option<String>,
    generation: Option<u64>,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Format {
    Plain,
    Ansi,
    Waybar,
    I3bar,
    Polybar,
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

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum ProcKind {
    Rebuild,
    NixBuild,
    Activate,
}

struct Proc {
    kind: ProcKind,
    elapsed: u64,
    argv: Vec<String>,
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
        let Some(_pid) = name.to_str().and_then(|s| s.parse::<u32>().ok()) else {
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
        let Some(ticks) = parse_starttime_ticks(&stat) else {
            continue;
        };
        let started = ticks as f64 / CLK_TCK as f64;
        let elapsed = if started >= uptime {
            0
        } else {
            (uptime - started) as u64
        };
        out.push(Proc {
            kind,
            elapsed,
            argv,
        });
    }
    out
}

/// Process classification. Shebang scripts (nixos-rebuild, nix-build,
/// switch-to-configuration) run as `interpreter script args...`, so argv[1]
/// counts as a program name — but only when it is a path, otherwise
/// `rg nixos-rebuild` would look like a rebuild.
fn classify(argv: &[String]) -> Option<ProcKind> {
    let head0 = argv.first().map(|a| basename(a));
    let head1 = argv.get(1).filter(|a| a.contains('/')).map(|a| basename(a));
    let matches = |name: &str| head0 == Some(name) || head1 == Some(name);
    let is_nix_build = |b: &str| b == "nix-build" || b.starts_with("nix-build-");

    if matches("nixos-rebuild") {
        return Some(ProcKind::Rebuild);
    }
    if matches("switch-to-configuration") || matches("switch-to-configuration-ng") {
        return Some(ProcKind::Activate);
    }
    if head0.is_some_and(is_nix_build) || head1.is_some_and(is_nix_build) {
        return Some(ProcKind::NixBuild);
    }
    if head0 == Some("nix") && argv.iter().skip(1).any(|a| a == "build") {
        return Some(ProcKind::NixBuild);
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

/// starttime is field 22 of /proc/<pid>/stat. The comm field (field 2) is
/// parenthesized and may contain spaces or parentheses, so parsing restarts
/// after the last ')'.
fn parse_starttime_ticks(stat: &str) -> Option<u64> {
    let close = stat.rfind(')')?;
    let rest: Vec<&str> = stat[close + 1..].split_ascii_whitespace().collect();
    rest.get(19)?.parse().ok()
}

fn oldest_of<'a>(procs: &'a [Proc], kind: ProcKind) -> Option<&'a Proc> {
    procs
        .iter()
        .filter(|p| p.kind == kind)
        .max_by_key(|p| p.elapsed)
}

// ---------------------------------------------------------------------------
// nixos-rebuild / nix build context extraction
// ---------------------------------------------------------------------------

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

fn rebuild_action(argv: &[String]) -> Option<String> {
    argv.iter()
        .skip(1)
        .find(|a| REBUILD_ACTIONS.contains(&a.as_str()))
        .cloned()
}

fn rebuild_host(argv: &[String]) -> Option<String> {
    if let Some(flake) = flag_value(argv, "--flake") {
        if let Some(host) = flake_host(flake) {
            return Some(host);
        }
    }
    argv.iter()
        .filter(|a| !a.starts_with('-'))
        .find_map(|a| attr_host(a).or_else(|| flake_host(a)))
}

fn build_host(argv: &[String]) -> Option<String> {
    if let Some(flake) = flag_value(argv, "--flake") {
        if let Some(host) = flake_host(flake) {
            return Some(host);
        }
    }
    argv.iter().find_map(|a| attr_host(a))
}

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
        Some(host)
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

    if !found.iter().any(|d| now - d.mtime <= fresh) {
        // Recently touched directories can only contain freshly created logs.
        scan_logs(log_root, now, fresh, false, &mut seen, &mut found);
        if found.is_empty() {
            // Cold start in the middle of a build: pay for the full walk once.
            scan_logs(log_root, now, fresh, true, &mut seen, &mut found);
        }
    }

    found.sort_by(|a, b| b.mtime.cmp(&a.mtime).then_with(|| a.name.cmp(&b.name)));
    found.truncate(STATE_MAX);
    save_state(
        state_path,
        &found.iter().map(|d| d.path.clone()).collect::<Vec<_>>(),
    );
    found.into_iter().map(|d| d.name).collect()
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
    let Ok(dirs) = fs::read_dir(root) else {
        return;
    };
    for dir in dirs.flatten() {
        let dir_path = dir.path();
        let Ok(meta) = dir.metadata() else {
            continue;
        };
        if !meta.is_dir() {
            continue;
        }
        if !all && now - meta.mtime() > fresh {
            // No file was created here recently, so nothing new is building.
            continue;
        }
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
            out.push(Drv { path, mtime, name });
        }
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

    let rebuild = oldest_of(&procs, ProcKind::Rebuild);
    let build = oldest_of(&procs, ProcKind::NixBuild);
    let activate = oldest_of(&procs, ProcKind::Activate);

    let (action, host) = match rebuild {
        Some(p) => (
            rebuild_action(&p.argv),
            rebuild_host(&p.argv).or_else(|| build.and_then(|b| build_host(&b.argv))),
        ),
        None => (None, build.and_then(|b| build_host(&b.argv))),
    };

    if let Some(p) = activate {
        return Status {
            kind: Kind::Activating,
            elapsed: Some(p.elapsed),
            drvs: Vec::new(),
            action,
            host,
            generation,
        };
    }

    let session = rebuild.or(build);
    match session {
        None => Status {
            kind: Kind::Idle,
            elapsed: None,
            drvs: Vec::new(),
            action: None,
            host: None,
            generation,
        },
        Some(p) => {
            let drvs = active_drvs(&paths.log_root, &paths.state, fresh);
            let kind = if drvs.is_empty() {
                Kind::Evaluating
            } else {
                Kind::Building
            };
            Status {
                kind,
                elapsed: Some(p.elapsed),
                drvs,
                action,
                host,
                generation,
            }
        }
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
    let mut detail = String::new();
    match s.kind {
        Kind::Idle => {
            if let Some(gen) = s.generation {
                detail = format!("gen {gen}");
            }
        }
        Kind::Evaluating | Kind::Activating => {
            if let Some(host) = &s.host {
                detail = host.clone();
            }
        }
        Kind::Building => {
            if let Some(name) = s.drvs.first() {
                detail = name.clone();
                if s.drvs.len() > 1 {
                    detail.push_str(&format!(" +{}", s.drvs.len() - 1));
                }
            }
        }
    }

    let drop_verb = o.compact && icon.is_some() && !detail.is_empty() && s.kind != Kind::Idle;
    let mut parts: Vec<String> = Vec::new();
    if let Some(glyph) = icon {
        parts.push(glyph.to_string());
    }
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
    let mut lines = vec![
        "NixOS build".to_string(),
        format!("state: {}", s.kind.word()),
    ];
    if s.kind == Kind::Building {
        if let Some(drv) = s.drvs.first() {
            lines.push(format!("derivation: {drv}"));
        }
        if s.drvs.len() > 1 {
            lines.push(format!("parallel: {}", s.drvs.len()));
        }
    }
    if let Some(secs) = s.elapsed {
        lines.push(format!("elapsed: {}", fmt_elapsed(secs)));
    }
    if let Some(action) = &s.action {
        lines.push(format!("action: {action}"));
    }
    if let Some(host) = &s.host {
        lines.push(format!("host: {host}"));
    }
    if let Some(gen) = s.generation {
        lines.push(format!("generation: {gen}"));
    }
    lines.join("\n")
}

fn render(s: &Status, o: &Opts) -> String {
    let text = build_text(s, o);
    match o.format {
        Format::Plain => text,
        Format::Ansi => {
            if o.no_color {
                text
            } else {
                format!("{}{}\x1b[0m", s.kind.ansi(), text)
            }
        }
        Format::Polybar => format!("%{{F{}}}{}%{{F-}}", s.kind.hex(), poly_escape(&text)),
        Format::Waybar => format!(
            "{{\"text\":\"{}\",\"alt\":\"{}\",\"class\":\"{}\",\"tooltip\":\"{}\"}}",
            json_escape(&text),
            s.kind.word(),
            s.kind.word(),
            json_escape(&tooltip(s))
        ),
        Format::I3bar => format!(
            "{{\"name\":\"nixbuild\",\"full_text\":\"{}\",\"color\":\"{}\",\"tooltip\":\"{}\"}}",
            json_escape(&text),
            s.kind.hex(),
            json_escape(&tooltip(s))
        ),
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

    match opts.watch {
        None => {
            let status = collect(&paths, DISCOVER_FRESH_SECS);
            let line = hide(status.kind, render(&status, &opts));
            if !emit(&line) {
                process::exit(0);
            }
        }
        Some(interval) => {
            let mut last: Option<String> = None;
            loop {
                let status = collect(&paths, DISCOVER_FRESH_SECS);
                let line = hide(status.kind, render(&status, &opts));
                if last.as_deref() != Some(line.as_str()) {
                    if !emit(&line) {
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

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(tag: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = env::temp_dir().join(format!("nbs-{}-{}-{tag}", process::id(), nanos));
        fs::create_dir_all(&path).unwrap();
        path
    }

    fn stat_line(pid: u32, comm: &str, start_ticks: u64) -> String {
        let mut fields: Vec<String> =
            vec![pid.to_string(), format!("({comm})"), "S".into(), "1".into()];
        while fields.len() < 21 {
            fields.push("0".into());
        }
        fields.push(start_ticks.to_string());
        fields.join(" ")
    }

    fn write_uptime(root: &Path, uptime: f64) {
        fs::write(root.join("uptime"), format!("{uptime} 0.00\n")).unwrap();
    }

    fn add_proc(root: &Path, pid: u32, argv: &[&str], elapsed_secs: u64) {
        let dir = root.join(pid.to_string());
        fs::create_dir_all(&dir).unwrap();
        let mut cmdline = Vec::new();
        for arg in argv {
            cmdline.extend_from_slice(arg.as_bytes());
            cmdline.push(0);
        }
        fs::write(dir.join("cmdline"), cmdline).unwrap();
        let uptime = 1000.0_f64;
        let start = ((uptime - elapsed_secs as f64) * CLK_TCK as f64) as u64;
        fs::write(dir.join("stat"), stat_line(pid, argv[0], start)).unwrap();
    }

    fn test_opts() -> Opts {
        Opts {
            format: Format::Plain,
            icons: Icons::Plain,
            compact: false,
            hide_idle: false,
            no_color: true,
            watch: None,
            help: false,
            version: false,
        }
    }

    fn fixture(tag: &str) -> (PathBuf, Paths) {
        let base = tmp(tag);
        let proc_root = base.join("proc");
        fs::create_dir_all(&proc_root).unwrap();
        write_uptime(&proc_root, 1000.0);
        let paths = Paths {
            proc_root,
            log_root: base.join("drvs"),
            state: base.join("state"),
            system_link: base.join("system"),
        };
        (base, paths)
    }

    #[test]
    fn parses_starttime_from_stat_with_spaces_in_comm() {
        let line = stat_line(4242, "some comm) with (spaces", 8800);
        assert_eq!(parse_starttime_ticks(&line), Some(8800));
    }

    #[test]
    fn classifies_processes() {
        let s = |v: &[&str]| v.iter().map(|a| a.to_string()).collect::<Vec<_>>();
        assert_eq!(
            classify(&s(&["/nix/store/x/bin/nixos-rebuild", "switch"])),
            Some(ProcKind::Rebuild)
        );
        // Shebang scripts appear as `interpreter script args...`.
        assert_eq!(
            classify(&s(&[
                "/nix/store/b/bin/bash",
                "/nix/store/x/bin/nixos-rebuild",
                "boot"
            ])),
            Some(ProcKind::Rebuild)
        );
        assert_eq!(
            classify(&s(&["/nix/store/x/bin/switch-to-configuration", "switch"])),
            Some(ProcKind::Activate)
        );
        assert_eq!(
            classify(&s(&["/nix/store/x/bin/nix-build", "default.nix"])),
            Some(ProcKind::NixBuild)
        );
        assert_eq!(
            classify(&s(&[
                "/nix/store/x/bin/nix",
                "--extra-experimental-features",
                "nix-command flakes",
                "build",
                ".#x"
            ])),
            Some(ProcKind::NixBuild)
        );
        assert_eq!(classify(&s(&["/usr/bin/rg", "nixos-rebuild"])), None);
        assert_eq!(
            classify(&s(&["/nix/store/x/bin/nix", "flake", "update"])),
            None
        );
    }

    #[test]
    fn extracts_rebuild_action_and_host() {
        let argv: Vec<String> = [
            "/nix/store/x/bin/nixos-rebuild",
            "switch",
            "--flake",
            "/etc/nixos#trantor",
        ]
        .iter()
        .map(|s| s.to_string())
        .collect();
        assert_eq!(rebuild_action(&argv).as_deref(), Some("switch"));
        assert_eq!(rebuild_host(&argv).as_deref(), Some("trantor"));

        let argv: Vec<String> = [
            "nixos-rebuild",
            "test",
            "-f",
            "<nixpkgs/nixos>",
            "-A",
            "nixosConfigurations.box.config.system.build.toplevel",
        ]
        .iter()
        .map(|s| s.to_string())
        .collect();
        assert_eq!(rebuild_action(&argv).as_deref(), Some("test"));
        assert_eq!(rebuild_host(&argv).as_deref(), Some("box"));
        assert_eq!(rebuild_action(&["nixos-rebuild".to_string()]), None);
    }

    #[test]
    fn parses_drv_log_names() {
        let hash = "a".repeat(32);
        assert_eq!(
            drv_name(&format!("{hash}-hello-2.12.drv.bz2")).as_deref(),
            Some("hello-2.12")
        );
        // Real log layout: only 30 hash characters in the file name.
        assert_eq!(
            drv_name("1arkrcj8z0a2pr5ki6bgn9fgbqlav9-nixbuild-status-0.1.0.drv.bz2").as_deref(),
            Some("nixbuild-status-0.1.0")
        );
        assert_eq!(drv_name("hello-2.12.drv").as_deref(), Some("hello-2.12"));
        assert_eq!(
            drv_name("0123456789abcdef0123456789abcdef-linux-6.18.drv.bz2").as_deref(),
            Some("linux-6.18")
        );
        assert_eq!(drv_name("not-a-log.txt"), None);
        assert_eq!(drv_name(".drv.bz2"), None);
    }

    #[test]
    fn formats_elapsed_time() {
        assert_eq!(fmt_elapsed(0), "0s");
        assert_eq!(fmt_elapsed(59), "59s");
        assert_eq!(fmt_elapsed(60), "1:00");
        assert_eq!(fmt_elapsed(3599), "59:59");
        assert_eq!(fmt_elapsed(3600), "1:00:00");
        assert_eq!(fmt_elapsed(3661), "1:01:01");
    }

    #[test]
    fn idle_status_reads_generation() {
        let (base, paths) = fixture("idle");
        add_proc(
            &paths.proc_root,
            1,
            &["/usr/lib/systemd/systemd", "--system"],
            9000,
        );
        fs::create_dir_all(base.join("profiles")).unwrap();
        std::os::unix::fs::symlink("system-42-link", base.join("system")).unwrap();

        let status = collect(&paths, DISCOVER_FRESH_SECS);
        assert_eq!(status.kind, Kind::Idle);
        assert_eq!(status.generation, Some(42));
        assert_eq!(render(&status, &test_opts()), "\u{2744} idle gen 42");
    }

    #[test]
    fn detects_building_and_remembers_the_derivation() {
        let (base, paths) = fixture("build");
        add_proc(
            &paths.proc_root,
            4242,
            &[
                "/nix/store/x-nixos-rebuild/bin/nixos-rebuild",
                "switch",
                "--flake",
                "/etc/nixos#trantor",
            ],
            12,
        );
        let dir = paths.log_root.join("xz");
        fs::create_dir_all(&dir).unwrap();
        let log = dir.join(format!("{}-hello-2.12.drv.bz2", "b".repeat(32)));
        fs::write(&log, b"building hello-2.12\n").unwrap();

        let status = collect(&paths, DISCOVER_FRESH_SECS);
        assert_eq!(status.kind, Kind::Building);
        assert_eq!(status.drvs, vec!["hello-2.12".to_string()]);
        assert_eq!(status.elapsed, Some(12));
        assert_eq!(status.action.as_deref(), Some("switch"));
        assert_eq!(status.host.as_deref(), Some("trantor"));
        assert_eq!(
            render(&status, &test_opts()),
            "\u{2699} building hello-2.12 12s"
        );

        // The state file carries the derivation, so a second (one-shot) run
        // does not need to walk the log directory again.
        let mut paths2 = paths.clone();
        paths2.log_root = base.join("drvs-empty");
        fs::create_dir_all(&paths2.log_root).unwrap();
        let again = collect(&paths2, DISCOVER_FRESH_SECS);
        assert_eq!(again.kind, Kind::Building);
        assert_eq!(again.drvs, vec!["hello-2.12".to_string()]);
    }

    #[test]
    fn reports_parallel_builds() {
        let (_base, paths) = fixture("parallel");
        add_proc(
            &paths.proc_root,
            7,
            &["/nix/store/x/bin/nix", "build", ".#x"],
            4,
        );
        let dir = paths.log_root.join("00");
        fs::create_dir_all(&dir).unwrap();
        for name in ["aaa-1.0", "bbb-2.0"] {
            fs::write(dir.join(format!("{}-{name}.drv.bz2", "c".repeat(32))), b"x").unwrap();
        }
        let status = collect(&paths, DISCOVER_FRESH_SECS);
        assert_eq!(status.kind, Kind::Building);
        assert_eq!(status.drvs.len(), 2);
        assert_eq!(status.elapsed, Some(4));
        assert_eq!(status.action, None);
        assert!(render(&status, &test_opts()).contains("+1"));
    }

    #[test]
    fn detects_activation_phase() {
        let (_base, paths) = fixture("activate");
        add_proc(
            &paths.proc_root,
            11,
            &["/nix/store/x/bin/switch-to-configuration", "switch"],
            3,
        );
        let status = collect(&paths, DISCOVER_FRESH_SECS);
        assert_eq!(status.kind, Kind::Activating);
        assert_eq!(status.elapsed, Some(3));
        assert_eq!(render(&status, &test_opts()), "\u{26a1} activating 3s");
    }

    #[test]
    fn evaluating_when_no_derivation_log_is_fresh() {
        let (_base, paths) = fixture("evaluating");
        add_proc(
            &paths.proc_root,
            5,
            &["/nix/store/x/bin/nix", "build", ".#trantor"],
            7,
        );
        let status = collect(&paths, DISCOVER_FRESH_SECS);
        assert_eq!(status.kind, Kind::Evaluating);
        assert_eq!(render(&status, &test_opts()), "\u{2026} evaluating 7s");
    }

    #[test]
    fn renders_waybar_json() {
        let status = Status {
            kind: Kind::Building,
            elapsed: Some(75),
            drvs: vec!["hello-2.12".to_string()],
            action: Some("switch".to_string()),
            host: Some("trantor".to_string()),
            generation: Some(42),
        };
        let mut opts = test_opts();
        opts.format = Format::Waybar;
        let line = render(&status, &opts);
        assert!(line.starts_with("{\"text\":\"\u{2699} building hello-2.12 1:15\""));
        assert!(line.contains("\"class\":\"building\""));
        assert!(line.contains("\"tooltip\":\"NixOS build\\nstate: building"));
        assert!(line.contains("derivation: hello-2.12"));
        assert!(line.ends_with("}"));

        let idle = Status {
            kind: Kind::Idle,
            elapsed: None,
            drvs: Vec::new(),
            action: None,
            host: None,
            generation: Some(42),
        };
        let line = render(&idle, &opts);
        assert!(line.contains("\"text\":\"\u{2744} idle gen 42\""));
        assert!(line.contains("\\nstate: idle"));
    }

    #[test]
    fn renders_polybar_and_escapes_markup() {
        let status = Status {
            kind: Kind::Building,
            elapsed: Some(5),
            drvs: vec!["perl-5.40.0%test".to_string()],
            action: None,
            host: None,
            generation: None,
        };
        let mut opts = test_opts();
        opts.format = Format::Polybar;
        assert_eq!(
            render(&status, &opts),
            "%{F#f9e2af}\u{2699} building perl-5.40.0%%test 5s%{F-}"
        );
    }

    #[test]
    fn compact_drops_the_verb_when_the_icon_and_detail_are_there() {
        let status = Status {
            kind: Kind::Building,
            elapsed: Some(12),
            drvs: vec!["hello-2.12".to_string()],
            action: None,
            host: None,
            generation: None,
        };
        let mut opts = test_opts();
        opts.compact = true;
        assert_eq!(render(&status, &opts), "\u{2699} hello-2.12 12s");
        opts.icons = Icons::None;
        assert_eq!(render(&status, &opts), "build hello-2.12 12s");
    }

    #[test]
    fn parses_cli_arguments() {
        let opts = parse_args(
            ["--format", "waybar", "--icons=none", "-w", "2.5"]
                .map(String::from)
                .to_vec(),
        )
        .unwrap();
        assert_eq!(opts.format, Format::Waybar);
        assert_eq!(opts.icons, Icons::None);
        assert_eq!(opts.watch, Some(Duration::from_secs_f64(2.5)));

        let opts = parse_args(vec!["-w".to_string()]).unwrap();
        assert_eq!(opts.watch, Some(Duration::from_secs(1)));
        assert_eq!(opts.format, Format::Plain);
        assert!(parse_args(vec!["--nope".to_string()]).is_err());
        assert!(parse_args(vec!["--format".to_string(), "yaml".to_string()]).is_err());
    }
}
