//! Rust port of `packages/local-bin/bin/mp`.
//!
//! Plays the arguments with `mpv` while spawning `vid-info` for the given files
//! and for the regular files inside the given directories, in the background.
//! `find`, `xargs`, `vid-info`, `mkdir` and `mpv` stay subprocesses with the
//! original argv; argument classification (`[ -d ]`/`[ -f ]`), the NUL list fed
//! to `xargs` and the `mpv.log` redirection are native.

use std::ffi::OsStr;
use std::fs::{self, File, OpenOptions};
use std::io::{Seek, SeekFrom, Write};
use std::os::unix::ffi::OsStrExt;
use std::path::Path;
use std::process::{Command, Stdio};

use local_bin_audio::env;
use local_bin_audio::helptext::MP_USAGE;
use local_bin_audio::proc::{spawn_error_code, Cmd};

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);
    let args: Vec<Vec<u8>> = arguments
        .map(|value| env::os_bytes(&value).to_vec())
        .collect();

    // `help_from_header 2 4 "$@"`: only the first argument is inspected.
    if let Some(first) = args.first() {
        if first == b"-h" || first == b"--help" {
            env::out_str(MP_USAGE);
            return;
        }
    }

    let home = env::var_or_empty("HOME");
    let mut vid_info = home.clone();
    vid_info.extend_from_slice(b"/.local/bin/vid-info");

    // `if [ -d "$arg" ]; then find -- "$arg" ... | xargs ... & fi`
    for argument in &args {
        let is_directory = fs::metadata(Path::new(OsStr::from_bytes(argument)))
            .map(|meta| meta.is_dir())
            .unwrap_or(false);
        if is_directory {
            spawn_directory_info(&program, argument);
        }
    }

    // The file block runs even with no file arguments: GNU xargs runs the
    // command once on empty input, exactly like the shell version.
    spawn_file_info(&program, &args, &vid_info);

    // `mkdir -p -- "$HOME/tmp"`
    let mut log_dir = home.clone();
    log_dir.extend_from_slice(b"/tmp");
    let _ = Cmd::new("mkdir")
        .arg("-p")
        .arg("--")
        .arg_bytes(&log_dir)
        .diag(&program, 25)
        .run();

    // `mpv --quiet -- "$@" > "$HOME/tmp/mpv.log" 2>&1`
    let mut log = log_dir;
    log.extend_from_slice(b"/mpv.log");
    run_mpv(&program, &args, &log);
}

/// `find -- DIR -maxdepth 1 -type f -print0 | xargs -0 -n10 -P 10 vid-info &`
fn spawn_directory_info(program: &[u8], directory: &[u8]) {
    let find = Command::new("find")
        .arg("--")
        .arg(OsStr::from_bytes(directory))
        .args(["-maxdepth", "1", "-type", "f", "-print0"])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn();
    match find {
        Ok(mut child) => {
            let stdin = match child.stdout.take() {
                Some(pipe) => Stdio::from(pipe),
                None => Stdio::null(),
            };
            let _ = background_xargs(stdin, &[b"vid-info".as_slice()], program, 16);
        }
        Err(error) => {
            env::err(&spawn_message(program, 16, b"find", &error));
            // The shell still starts xargs; with a failed producer it sees EOF.
            let _ = background_xargs(Stdio::null(), &[b"vid-info".as_slice()], program, 16);
        }
    }
}

/// `{ for arg in "$@"; do [ -f "$arg" ] && printf '%s\0' "$arg"; done \
///      | xargs -0 -n10 -P 10 ~/.local/bin/vid-info; } &`
fn spawn_file_info(program: &[u8], args: &[Vec<u8>], vid_info: &[u8]) {
    let mut payload = Vec::new();
    for argument in args {
        let is_file = fs::metadata(Path::new(OsStr::from_bytes(argument)))
            .map(|meta| meta.is_file())
            .unwrap_or(false);
        if is_file {
            payload.extend_from_slice(argument);
            payload.push(0);
        }
    }
    match spool(&payload) {
        Some(file) => {
            let _ = background_xargs(Stdio::from(file), &[vid_info], program, 23);
        }
        None => {
            // Spooling failed; feed the pipe directly so the argv is unchanged.
            let mut command = Command::new("xargs");
            command
                .args(["-0", "-n10", "-P", "10"])
                .arg(OsStr::from_bytes(vid_info))
                .stdin(Stdio::piped())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit());
            match command.spawn() {
                Ok(mut child) => {
                    if let Some(mut pipe) = child.stdin.take() {
                        let _ = pipe.write_all(&payload);
                    }
                }
                Err(error) => {
                    env::err(&spawn_message(program, 23, b"xargs", &error));
                }
            }
        }
    }
}

/// Start `xargs -0 -n10 -P 10 ARGS...` in the background and never wait; the
/// shell backgrounds the whole pipeline the same way.
fn background_xargs(
    stdin: Stdio,
    tools: &[&[u8]],
    program: &[u8],
    line: u32,
) -> Option<std::process::Child> {
    let mut command = Command::new("xargs");
    command
        .args(["-0", "-n10", "-P", "10"])
        .stdin(stdin)
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());
    for tool in tools {
        command.arg(OsStr::from_bytes(tool));
    }
    match command.spawn() {
        Ok(child) => Some(child),
        Err(error) => {
            env::err(&spawn_message(program, line, b"xargs", &error));
            None
        }
    }
}

/// Put the NUL-separated payload in an unlinked file: passing it as xargs stdin
/// keeps the writer out of the port's process (the shell's producer is a
/// background subshell) without a pipe that could block `mpv` startup.
fn spool(payload: &[u8]) -> Option<File> {
    let dir = env::var_nonempty("TMPDIR").unwrap_or_else(|| b"/tmp".to_vec());
    for attempt in 0..64 {
        let mut path = dir.clone();
        path.extend_from_slice(
            format!("/local-bin-audio-mp-{}-{}.nul", std::process::id(), attempt).as_bytes(),
        );
        let path = Path::new(OsStr::from_bytes(&path));
        match OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .open(path)
        {
            Ok(mut file) => {
                file.write_all(payload).ok()?;
                file.seek(SeekFrom::Start(0)).ok()?;
                let _ = fs::remove_file(path);
                return Some(file);
            }
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(_) => return None,
        }
    }
    None
}

/// `mpv --quiet -- ARGS... > LOG 2>&1`, exiting with mpv's status.
fn run_mpv(program: &[u8], args: &[Vec<u8>], log: &[u8]) -> ! {
    let path = Path::new(OsStr::from_bytes(log));
    let file = match File::create(path) {
        Ok(file) => file,
        Err(error) => {
            env::err(&env::redirect_failure_message(program, 26, log, &error));
            std::process::exit(1);
        }
    };
    let error_file = match file.try_clone() {
        Ok(clone) => clone,
        Err(_) => std::process::exit(1),
    };
    let mut command = Command::new("mpv");
    command.args(["--quiet", "--"]);
    for argument in args {
        command.arg(OsStr::from_bytes(argument));
    }
    command
        .stdin(Stdio::inherit())
        .stdout(Stdio::from(file))
        .stderr(Stdio::from(error_file));
    match command.status() {
        Ok(status) => std::process::exit(env::status_code(status)),
        Err(error) => {
            // The shell's diagnostic is written after the redirection, so it
            // lands in the log file.
            if let Ok(mut log_file) = OpenOptions::new().append(true).open(path) {
                let _ = log_file.write_all(&env::not_found_message(program, 26, b"mpv"));
            }
            std::process::exit(spawn_error_code(&error));
        }
    }
}

fn spawn_message(program: &[u8], line: u32, tool: &[u8], error: &std::io::Error) -> Vec<u8> {
    if tool.contains(&b'/') {
        env::path_failure_message(program, line, tool, error)
    } else {
        env::not_found_message(program, line, tool)
    }
}
