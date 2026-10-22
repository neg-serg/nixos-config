//! `tint` — a fast colouriser for command-line programs.
//!
//! Two ways in:
//!
//! - wrapper: `tint -- df -h` runs `df` and colours what it prints. When the
//!   output is not a terminal the command is `exec`ed, so a pipe pays nothing.
//! - filter: `df -h | tint -r df` colours what it is given.
//!
//! The colouring itself is described in `scan.rs` (type-directed classifiers),
//! `ruleset.rs` (per-tool deltas) and `theme.rs` (semantic slots → colours).

mod config;
mod engine;
mod fast;
mod hit;
mod pty;
mod rule;
mod ruleset;
mod scan;
mod shell;
mod style;
mod theme;

use std::io::{self, IsTerminal, Read, Write};
use std::os::fd::AsRawFd;
#[cfg(unix)]
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Command, ExitStatus, Stdio};
use std::time::Instant;

use engine::{AnsiPolicy, Engine};
use theme::{Kind, Theme};

const VERSION: &str = env!("CARGO_PKG_VERSION");

fn main() {
    std::process::exit(run());
}

/// Parsed command line.
#[derive(Default)]
struct Args {
    ruleset: Option<String>,
    theme: Option<String>,
    color: Option<String>,
    ansi: Option<String>,
    config: Option<String>,
    stats: bool,
    /// Give the child a terminal of its own (`--pty`).
    pty: bool,
    /// Page the colourised output (`--pager`).
    pager: bool,
    list: bool,
    show: Option<String>,
    shell: Option<String>,
    help: bool,
    version: bool,
    command: Vec<String>,
}

fn run() -> i32 {
    let args = match parse_args(std::env::args().skip(1).collect()) {
        Ok(args) => args,
        Err(message) => {
            eprintln!("tint: {message}");
            eprintln!("try `tint --help`");
            return 2;
        }
    };
    if args.help {
        print!("{}", help_text());
        return 0;
    }
    if args.version {
        println!("tint {VERSION}");
        return 0;
    }

    let config = match load_config(args.config.as_deref()) {
        Ok(config) => config,
        Err(message) => {
            eprintln!("tint: {message}");
            return 2;
        }
    };

    if args.list {
        print!("{}", list_rulesets());
        return 0;
    }
    if let Some(name) = args.show.as_deref() {
        let theme_name = args
            .theme
            .clone()
            .or_else(|| config.theme.clone())
            .unwrap_or_else(|| "dark".to_string());
        match show_ruleset(name, &config, &theme_name) {
            Ok(text) => {
                print!("{text}");
                return 0;
            }
            Err(message) => {
                eprintln!("tint: {message}");
                return 2;
            }
        }
    }
    if let Some(shell) = args.shell.as_deref() {
        match shell::emit(shell, &config) {
            Ok(text) => {
                print!("{text}");
                return 0;
            }
            Err(message) => {
                eprintln!("tint: {message}");
                return 2;
            }
        }
    }

    let ruleset_name = match args.ruleset.clone() {
        Some(name) => name,
        None => args
            .command
            .first()
            .map(|command| ruleset::for_command(command).to_string())
            .unwrap_or_else(|| "generic".to_string()),
    };
    let Some(def) = ruleset::find(&ruleset_name) else {
        eprintln!("tint: unknown ruleset `{ruleset_name}` (see `tint --list`)");
        return 2;
    };

    let theme_name = args
        .theme
        .clone()
        .or_else(|| config.theme.clone())
        .unwrap_or_else(|| "dark".to_string());
    let Some(theme) = Theme::by_name(&theme_name) else {
        eprintln!("tint: unknown theme `{theme_name}` (dark, neg, light, vivid, mono, none)");
        return 2;
    };

    let ansi_name = args.ansi.clone().unwrap_or_else(|| "skip".to_string());
    let Some(ansi) = AnsiPolicy::by_name(&ansi_name) else {
        eprintln!("tint: unknown --ansi value `{ansi_name}` (skip, extend)");
        return 2;
    };

    let color = match resolve_color(args.color.as_deref().or(config.color.as_deref())) {
        Ok(color) => color,
        Err(message) => {
            eprintln!("tint: {message}");
            return 2;
        }
    };

    let engine = Engine::build(def, &config, theme, ansi);
    let started = Instant::now();

    let status = if args.command.is_empty() {
        match filter(&engine, color, args.stats) {
            Ok(stats) => {
                if args.stats {
                    print_stats(&stats, started);
                }
                0
            }
            // `tint ... | head -1` closes the pipe under us; that is not an error.
            Err(err) if err.kind() == io::ErrorKind::BrokenPipe => 0,
            Err(err) => {
                eprintln!("tint: {err}");
                1
            }
        }
    } else if args.pty {
        match run_pty(&engine, &args.command) {
            Ok(outcome) => {
                if args.stats {
                    print_stats(&outcome.stats, started);
                }
                outcome.code
            }
            Err(err) => {
                eprintln!("tint: {}", err.message);
                err.code
            }
        }
    } else if args.pager {
        match run_pager(&engine, &args.command, color) {
            Ok(outcome) => {
                if args.stats {
                    print_stats(&outcome.stats, started);
                }
                outcome.code
            }
            Err(err) => {
                eprintln!("tint: {}", err.message);
                err.code
            }
        }
    } else {
        match wrap(&engine, &args.command, color) {
            Ok(outcome) => {
                if args.stats {
                    print_stats(&outcome.stats, started);
                }
                outcome.code
            }
            Err(err) => {
                eprintln!("tint: {}", err.message);
                err.code
            }
        }
    };
    status
}

fn parse_args(argv: Vec<String>) -> Result<Args, String> {
    let mut args = Args::default();
    let mut i = 0;
    while i < argv.len() {
        let arg = argv[i].clone();
        if arg == "--" {
            args.command.extend_from_slice(&argv[i + 1..]);
            return Ok(args);
        }
        if !arg.starts_with('-') || arg == "-" {
            args.command.extend_from_slice(&argv[i..]);
            return Ok(args);
        }
        let (flag, inline) = match arg.split_once('=') {
            Some((flag, value)) => (flag.to_string(), Some(value.to_string())),
            None => (arg.clone(), None),
        };
        macro_rules! value {
            () => {
                take_value(&argv, &mut i, inline.as_deref(), &flag)?
            };
        }
        match flag.as_str() {
            "-h" | "--help" => args.help = true,
            "-V" | "--version" => args.version = true,
            "--list" => args.list = true,
            "--stats" => args.stats = true,
            "--pty" => args.pty = true,
            "--pager" => args.pager = true,
            "--no-pager" => args.pager = false,
            "-r" | "--ruleset" => args.ruleset = Some(value!()),
            "-t" | "--theme" => args.theme = Some(value!()),
            "--color" | "--colour" => args.color = Some(value!()),
            "--ansi" => args.ansi = Some(value!()),
            "-c" | "--config" => args.config = Some(value!()),
            "--show" => args.show = Some(value!()),
            "--shell" => args.shell = Some(value!()),
            "--no-color" | "--no-colour" => args.color = Some("never".to_string()),
            other => return Err(format!("unknown option `{other}`")),
        }
        i += 1;
    }
    Ok(args)
}

/// Value of an option, either inline (`--theme=dark`) or the next argument.
fn take_value(
    argv: &[String],
    i: &mut usize,
    inline: Option<&str>,
    flag: &str,
) -> Result<String, String> {
    if let Some(value) = inline {
        return Ok(value.to_string());
    }
    *i += 1;
    argv.get(*i)
        .cloned()
        .ok_or_else(|| format!("`{flag}` needs a value"))
}

/// Read and parse the config file; a missing default file is not an error.
fn load_config(path: Option<&str>) -> Result<config::Config, String> {
    let (path, required) = match path {
        Some(path) => (PathBuf::from(path), true),
        None => (default_config_path(), false),
    };
    match std::fs::read_to_string(&path) {
        Ok(text) => config::parse(&text).map_err(|err| format!("{}: {err}", path.display())),
        Err(err) => {
            if required || err.kind() != io::ErrorKind::NotFound {
                Err(format!("{}: {err}", path.display()))
            } else {
                Ok(config::Config::default())
            }
        }
    }
}

fn default_config_path() -> PathBuf {
    if let Some(dir) = std::env::var_os("XDG_CONFIG_HOME") {
        if !dir.is_empty() {
            return PathBuf::from(dir).join("tint").join("config.toml");
        }
    }
    let home = std::env::var_os("HOME").unwrap_or_default();
    PathBuf::from(home)
        .join(".config")
        .join("tint")
        .join("config.toml")
}

/// Decide whether to colour, honouring the usual environment conventions.
fn resolve_color(explicit: Option<&str>) -> Result<bool, String> {
    let mode = explicit.unwrap_or("auto");
    match mode {
        "always" | "yes" | "force" | "true" => Ok(true),
        "never" | "no" | "off" | "false" => Ok(false),
        "auto" | "tty" => {
            if std::env::var_os("NO_COLOR").is_some() {
                return Ok(false);
            }
            let forced = ["CLICOLOR_FORCE", "FORCE_COLOR"]
                .iter()
                .any(|name| std::env::var_os(name).map(|v| v != "0").unwrap_or(false));
            if forced {
                return Ok(true);
            }
            if std::env::var("TERM")
                .map(|term| term == "dumb")
                .unwrap_or(false)
            {
                return Ok(false);
            }
            Ok(io::stdout().is_terminal())
        }
        other => Err(format!(
            "unknown --color value `{other}` (auto, always, never)"
        )),
    }
}

fn print_stats(stats: &engine::Stats, started: Instant) {
    let elapsed = started.elapsed();
    let millis = elapsed.as_secs_f64() * 1000.0;
    let throughput = if elapsed.as_secs_f64() > 0.0 {
        stats.bytes as f64 / elapsed.as_secs_f64() / (1024.0 * 1024.0)
    } else {
        0.0
    };
    eprintln!(
        "tint: {} lines, {} bytes, {} spans, {:.1} ms, {:.1} MiB/s",
        stats.lines, stats.bytes, stats.spans, millis, throughput
    );
}

/// Colourise stdin.
fn filter(engine: &Engine, color: bool, count: bool) -> io::Result<engine::Stats> {
    let stdin = io::stdin();
    let stdout = io::stdout();
    if !color {
        let mut input = stdin.lock();
        let mut output = stdout.lock();
        if !count {
            io::copy(&mut input, &mut output)?;
            output.flush()?;
            return Ok(engine::Stats::default());
        }
        // `--stats` with colour off still reports what went through.
        let mut stats = engine::Stats::default();
        let mut buf = vec![0u8; 64 * 1024];
        loop {
            let read = input.read(&mut buf)?;
            if read == 0 {
                break;
            }
            stats.bytes += read as u64;
            stats.lines += buf[..read].iter().filter(|b| **b == b'\n').count() as u64;
            output.write_all(&buf[..read])?;
        }
        output.flush()?;
        return Ok(stats);
    }
    engine::process(engine, stdin.lock(), stdout.lock())
}

/// Outcome of running a wrapped command.
struct Outcome {
    code: i32,
    stats: engine::Stats,
}

struct Failure {
    code: i32,
    message: String,
}

/// Run a command and colourise its stdout and stderr.
fn wrap(engine: &Engine, argv: &[String], color: bool) -> Result<Outcome, Failure> {
    let program = &argv[0];
    let mut command = Command::new(program);
    command.args(&argv[1..]);

    if !color {
        // No colour: replace ourselves with the command. One `exec`, no copy,
        // no exit-code translation.
        let err = command.exec();
        return Err(Failure {
            code: if err.kind() == io::ErrorKind::NotFound {
                127
            } else {
                126
            },
            message: format!("{program}: {err}"),
        });
    }

    command.stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = command.spawn().map_err(|err| Failure {
        code: if err.kind() == io::ErrorKind::NotFound {
            127
        } else {
            126
        },
        message: format!("{program}: {err}"),
    })?;
    let stdout = child.stdout.take().expect("piped stdout");
    let stderr = child.stderr.take().expect("piped stderr");

    let (out_result, err_result) = std::thread::scope(|scope| {
        let out_handle = scope.spawn(|| engine::process(engine, stdout, io::stdout()));
        let err_handle = scope.spawn(|| engine::process(engine, stderr, io::stderr()));
        (out_handle.join(), err_handle.join())
    });

    let mut stats = engine::Stats::default();
    for result in [out_result, err_result] {
        match result {
            Ok(Ok(part)) => {
                stats.lines += part.lines;
                stats.bytes += part.bytes;
                stats.spans += part.spans;
            }
            Ok(Err(err)) => {
                // A closed pipe is normal (`tint df | head -1`).
                if err.kind() != io::ErrorKind::BrokenPipe {
                    eprintln!("tint: {err}");
                }
            }
            Err(_) => {}
        }
    }

    let status = child.wait().map_err(|err| Failure {
        code: 126,
        message: format!("{program}: {err}"),
    })?;
    Ok(Outcome {
        code: exit_code(status),
        stats,
    })
}

/// Page the colourised output: the child writes into a pipe, we colour it into
/// the pager's stdin, and the pager draws on the real terminal. This is what
/// makes `git log`, `journalctl` and `systemctl status` wrappable without taking
/// their paging away.
fn run_pager(engine: &Engine, argv: &[String], color: bool) -> Result<Outcome, Failure> {
    let program = &argv[0];
    if !color {
        // No colour: nothing to page through us, just run it.
        let err = Command::new(program).args(&argv[1..]).exec();
        return Err(Failure {
            code: if err.kind() == io::ErrorKind::NotFound {
                127
            } else {
                126
            },
            message: format!("{program}: {err}"),
        });
    }
    let mut child = Command::new(program)
        .args(&argv[1..])
        .stdout(Stdio::piped())
        .spawn()
        .map_err(|err| Failure {
            code: if err.kind() == io::ErrorKind::NotFound {
                127
            } else {
                126
            },
            message: format!("{program}: {err}"),
        })?;
    let child_out = child.stdout.take().expect("piped stdout");

    let mut pager = Command::new("sh")
        .arg("-c")
        .arg(pager_command())
        .stdin(Stdio::piped())
        .spawn()
        .ok();
    let pager_stdin = pager.as_mut().and_then(|pager| pager.stdin.take());

    let mut stats = engine::Stats::default();
    let mut broken_pipe = false;
    match pager_stdin {
        Some(pipe) => match engine::process(engine, child_out, pipe) {
            Ok(counted) => stats = counted,
            // The pager was quit: the child gets SIGPIPE, we stop reading.
            Err(err) if err.kind() == io::ErrorKind::BrokenPipe => broken_pipe = true,
            Err(err) => {
                return Err(Failure {
                    code: 1,
                    message: err.to_string(),
                })
            }
        },
        None => {
            let stdout = io::stdout();
            stats = engine::process(engine, child_out, stdout).map_err(|err| Failure {
                code: 1,
                message: err.to_string(),
            })?;
        }
    }

    let status = child.wait().map_err(|err| Failure {
        code: 126,
        message: format!("{program}: {err}"),
    })?;
    if let Some(mut pager) = pager {
        let _ = pager.wait();
    }
    Ok(Outcome {
        code: if broken_pipe { 0 } else { exit_code(status) },
        stats,
    })
}

/// The pager to use: `$TINT_PAGER`, then `$PAGER`, then `less -FRX` (raw
/// colours, quit when the output fits one screen, no screen clearing).
fn pager_command() -> String {
    ["TINT_PAGER", "PAGER"]
        .iter()
        .find_map(|name| std::env::var(name).ok())
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty() && value != "cat")
        .unwrap_or_else(|| "less -FRX".to_string())
}

/// Run the child on a pty of its own and relay the terminal through the
/// colouriser (see `pty.rs`). Progress bars, `-it` and pagers keep working
/// because the child really does see a terminal.
fn run_pty(engine: &Engine, argv: &[String]) -> Result<Outcome, Failure> {
    let program = &argv[0];
    let mut pty = pty::Pty::open().map_err(|err| Failure {
        code: 1,
        message: format!("--pty: cannot allocate a pty: {err}"),
    })?;
    let stdin = io::stdin();
    let stdout = io::stdout();
    let stdin_fd = stdin.as_raw_fd();
    pty::Pty::copy_winsize(
        if stdout.is_terminal() {
            stdout.as_raw_fd()
        } else {
            stdin_fd
        },
        pty.master_fd(),
    );
    let raw = if stdin.is_terminal() {
        pty::RawMode::enable(stdin_fd)
    } else {
        None
    };
    let mut child = pty.spawn(program, &argv[1..]).map_err(|err| Failure {
        code: if err.kind() == io::ErrorKind::NotFound {
            127
        } else {
            126
        },
        message: format!("{program}: {err}"),
    })?;
    pty.close_slave();
    let mut out = io::stdout();
    let stats = pty::relay(engine, pty.master_fd(), stdin_fd, &mut out).map_err(|err| Failure {
        code: 1,
        message: format!("--pty ({}): {err}", pty.name),
    })?;
    let status = child.wait().map_err(|err| Failure {
        code: 126,
        message: format!("{program}: {err}"),
    })?;
    drop(raw);
    Ok(Outcome {
        code: exit_code(status),
        stats,
    })
}

fn exit_code(status: ExitStatus) -> i32 {
    if let Some(code) = status.code() {
        return code;
    }
    #[cfg(unix)]
    {
        use std::os::unix::process::ExitStatusExt;
        if let Some(signal) = status.signal() {
            return 128 + signal;
        }
    }
    1
}

fn list_rulesets() -> String {
    let mut out = String::new();
    for def in ruleset::RULESETS {
        let mut flags = Vec::new();
        if def.flags.numbers {
            flags.push("numbers");
        }
        if def.flags.headers {
            flags.push("headers");
        }
        let flags = if flags.is_empty() {
            String::new()
        } else {
            format!(" [{}]", flags.join(", "))
        };
        out.push_str(&format!("{:<16} {}{}\n", def.name, def.about, flags));
    }
    out
}

fn show_ruleset(name: &str, config: &config::Config, theme_name: &str) -> Result<String, String> {
    let Some(def) = ruleset::find(name) else {
        return Err(format!("unknown ruleset `{name}` (see `tint --list`)"));
    };
    let Some(theme) = Theme::by_name(theme_name) else {
        return Err(format!("unknown theme `{theme_name}`"));
    };
    let engine = Engine::build(def, config, theme, AnsiPolicy::Skip);
    let mut out = String::new();
    out.push_str(&format!("ruleset: {}\n{}\n\n", def.name, def.about));
    out.push_str(&format!(
        "scanners: numbers={} headers={} ports={} keyval={}\n",
        def.flags.numbers, def.flags.headers, def.flags.ports, def.flags.keyval
    ));
    out.push_str(&format!(
        "compiled rules: {} ({} in this ruleset, {} from config), custom styles: {}\n\n",
        engine.rule_count(),
        def.words.len() + def.lines.len() + def.parts.len(),
        config.rules.len(),
        config.styles.len()
    ));
    out.push_str("words:\n");
    for (word, kind) in def.words {
        out.push_str(&format!("  {word:<24} {kind:?}\n"));
    }
    out.push_str("line prefixes:\n");
    for (prefix, kind) in def.lines {
        out.push_str(&format!("  {prefix:<24?} {kind:?}\n"));
    }
    let mut commands: Vec<&str> = Vec::new();
    for (ruleset, names) in ruleset::WRAPPERS {
        if *ruleset == def.name {
            commands.extend(names.iter().copied());
        }
    }
    if !commands.is_empty() {
        out.push_str(&format!("\nwraps: {}\n", commands.join(", ")));
    }
    if ruleset::EXPLICIT_ONLY.contains(&def.name) {
        out.push_str(&format!(
            "\nnot wrapped: this one owns a pager, a progress bar or a tty; use `cmd | tint -r {}`\n",
            def.name
        ));
    }
    if !config.rules.is_empty() {
        out.push_str(&format!(
            "\ncustom rules from config: {} (applied to every ruleset)\n",
            config.rules.len()
        ));
    }
    Ok(out)
}

fn help_text() -> String {
    format!(
        "tint {VERSION} — fast colouriser for command-line program output

USAGE
  tint [OPTIONS] [--] COMMAND [ARGS...]    run COMMAND, colourise what it prints
  tint [OPTIONS] -r RULESET                colourise stdin (a pipeline)
  tint --list | --show RULESET | --shell SHELL

OPTIONS
  -r, --ruleset NAME   ruleset to use; inferred from COMMAND when omitted
  -t, --theme NAME     dark | neg | light | vivid | mono | none (default: dark)
      --color WHEN     auto | always | never                  (default: auto)
      --ansi WHEN      skip | extend   lines that already carry ANSI escapes
                       are passed through (skip) or re-coloured (extend)
      --pty            give the child a terminal of its own (progress bars,
                       `-it`, REPLs keep working); screen-control output is
                       relayed untouched
      --pager          page the colourised output (`$TINT_PAGER`, `$PAGER`,
                       else `less -FRX`)
  -c, --config PATH    config file, default $XDG_CONFIG_HOME/tint/config.toml
      --stats          counters and throughput on stderr
  -h, --help           this text
  -V, --version        version

SHELL INTEGRATION
  eval \"$(tint --shell zsh)\"      wraps every tool in the builtin table
  tint --shell fish | source      same for fish
  tint --shell list               ruleset and wrapped command per line

CONFIG (flat TOML subset)
  theme = \"dark\"
  color = \"auto\"
  theme.style.warn = \"yellow,bold\"     restyle a semantic slot
  wrap = \"go rustup\"                   wrap extra commands
  skip = \"find tar\"                    never wrap these
  pty = \"cargo rustc\"                  wrap with --pty (terminal of its own)
  pager = \"journalctl\"                 wrap with --pager (page the colour)
  keyword.FATAL = \"red,bold\"           word rule; value is a style or a slot
  \"prefix.!!!\" = \"brightred\"          line-start rule
  suffix.done = \"ok\"                   line-end rule
  \"literal.dbg!\" = \"idx:141\"          anywhere in the line

  A key whose needle has punctuation is quoted so the file stays valid TOML.

  Style values: colour names (red, brightblue, ...), #rrggbb, idx:N,
  on-<colour> for a background, and the attributes bold, dim, italic,
  underline. Slot names reuse the active theme:

    {}

  A rule value is either a slot name or a raw style.

ENVIRONMENT
  NO_COLOR disables colour, CLICOLOR_FORCE/FORCE_COLOR force it, TERM=dumb
  disables it. Pipes are never coloured unless --color=always is given.

RULESETS
{}",
        Kind::ALL
            .iter()
            .map(|kind| kind.name())
            .collect::<Vec<_>>()
            .join(" "),
        list_rulesets()
    )
}
