//! Rust port of `packages/local-bin/bin/pl`.
//!
//! fzf (or vicinae dmenu) picks videos from a directory, `wl-copy` mirrors the
//! selection, and mpv plays it through the shared IPC socket; `pl cmd` forwards
//! to playerctl and `pl vol` drives `vset` with an `amixer` fallback.
//!
//! The original spawns `~/bin/vid-info` in the background for every directory
//! and for the picked files. That shape is preserved: find/xargs run detached
//! with their original argv and their diagnostics go to the same place as in
//! the shell (stderr, or `~/tmp/mpv.log` for mpv).

#![forbid(unsafe_code)]

use std::ffi::{OsStr, OsString};
use std::fs::OpenOptions;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::path::Path;
use std::process::Stdio;

use local_bin_zsh::{
    capture, expand_tilde, home, is_executable, join_bytes, need, out_str, raw_args,
    redirection_failure, run, spawn_stdin_bytes, spawn_stdin_from, spawn_stdout_piped,
    var_nonempty, which_str, Captured, Site, Stderr, Stdin, Stdout,
};

const USAGE: &str = include_str!("pl_usage.txt");
const PROMPT: &str = "⟬vid⟭ ❯>";
const CMD_LINE: u32 = 134;
const VOL_LINE: u32 = 137;

fn videos_default() -> OsString {
    var_nonempty("XDG_VIDEOS_DIR").unwrap_or_else(|| join_bytes(&home(), b"/vid"))
}

/// `${1:-default}` followed by `${~dir}`: an empty first argument selects the
/// default, and a leading `~/` expands against HOME.
fn resolve_dir(argument: &OsStr) -> OsString {
    let value = if argument.is_empty() {
        videos_default()
    } else {
        argument.to_os_string()
    };
    expand_tilde(&value, &home())
}

fn find_candidates(directory: &OsStr, maxdepth: &OsStr) -> Captured {
    if which_str("fd").is_some() {
        let mut arguments: Vec<OsString> = vec![
            OsString::from("-t"),
            OsString::from("f"),
            OsString::from("--hidden"),
            OsString::from("--follow"),
            OsString::from("-E"),
            OsString::from(".git"),
            OsString::from("-E"),
            OsString::from("node_modules"),
            OsString::from("-E"),
            OsString::from("*.srt"),
        ];
        if !maxdepth.is_empty() {
            arguments.push(OsString::from("-d"));
            arguments.push(maxdepth.to_os_string());
        }
        arguments.push(OsString::from("."));
        arguments.push(directory.to_os_string());
        capture(
            Site::Func("find_candidates", 7),
            "fd",
            &arguments,
            Stdin::Null,
            Stderr::Inherit,
        )
    } else {
        let mut arguments: Vec<OsString> = vec![
            OsString::from("--files"),
            OsString::from("--hidden"),
            OsString::from("--follow"),
            OsString::from("-g"),
            OsString::from("!{.git,node_modules}/*"),
            OsString::from("-g"),
            OsString::from("!*.srt"),
        ];
        if !maxdepth.is_empty() {
            arguments.push(OsString::from("--max-depth"));
            arguments.push(maxdepth.to_os_string());
        }
        arguments.push(directory.to_os_string());
        capture(
            Site::Func("find_candidates", 12),
            "rg",
            &arguments,
            Stdin::Null,
            Stderr::Inherit,
        )
    }
}

/// `print -r -- "$sel" | wl-copy || true`: `print` appends a newline and the
/// exit status is ignored.
fn wl_copy(site: Site, selection: &[u8]) {
    let mut input = selection.to_vec();
    input.push(b'\n');
    run(
        site,
        "wl-copy",
        &[],
        Stdin::Bytes(input),
        Stdout::Inherit,
        Stderr::Inherit,
    );
}

fn pl_fzf(argument: &OsStr, maxdepth: &OsStr) -> i32 {
    need("fzf");
    let directory = resolve_dir(argument);
    let candidates = find_candidates(&directory, maxdepth);
    let selection = capture(
        Site::Func("pl_fzf", 5),
        "fzf",
        &[
            OsString::from("--multi"),
            OsString::from("--prompt"),
            OsString::from(PROMPT),
        ],
        Stdin::Bytes(candidates.stdout),
        Stderr::Inherit,
    )
    .text();
    if selection.is_empty() {
        return 0;
    }
    wl_copy(Site::Func("pl_fzf", 7), &selection);

    let mut targets: Vec<OsString> = Vec::new();
    for line in selection.split(|byte| *byte == b'\n') {
        if line.is_empty() {
            continue;
        }
        if line.starts_with(b"/") {
            targets.push(OsString::from_vec(line.to_vec()));
        } else {
            let mut target = directory.as_bytes().to_vec();
            target.push(b'/');
            target.extend_from_slice(line);
            targets.push(OsString::from_vec(target));
        }
    }
    // `(( ${#targets[@]} )) && mp ...`: an all-blank selection leaves the
    // arithmetic test as the last command, i.e. status 1.
    if targets.is_empty() {
        1
    } else {
        mp(&targets)
    }
}

fn pl_dmenu(argument: &OsStr, maxdepth: &OsStr) -> i32 {
    let directory = resolve_dir(argument);
    let list = find_candidates(&directory, maxdepth).text();
    if list.is_empty() {
        return 0;
    }
    // `${#${(f)list}[@]}` from the original: for a listing with two or more
    // lines zsh yields the element count, but for a single line it yields the
    // *character* count of that line. The `> 1` test therefore sends every
    // single candidate longer than one character to vicinae as well.
    let lines: Vec<&[u8]> = list
        .split(|byte| *byte == b'\n')
        .filter(|line| !line.is_empty())
        .collect();
    let count = match lines.as_slice() {
        [] => 0,
        [only] => zsh_char_count(only),
        many => many.len(),
    };
    let selection = if count > 1 {
        let mut input = list.clone();
        input.push(b'\n');
        capture(
            Site::Func("pl_dmenu", 10),
            "vicinae",
            &[
                OsString::from("dmenu"),
                OsString::from("-p"),
                OsString::from(PROMPT),
            ],
            Stdin::Bytes(input),
            Stderr::Inherit,
        )
        .text()
    } else {
        list
    };
    if selection.is_empty() {
        return 0;
    }
    wl_copy(Site::Func("pl_dmenu", 15), &selection);
    let target = if selection.starts_with(b"/") {
        OsString::from_vec(selection)
    } else {
        let mut target = directory.as_bytes().to_vec();
        target.push(b'/');
        target.extend_from_slice(&selection);
        OsString::from_vec(target)
    };
    mp(&[target])
}

/// `${#value}`: characters in UTF-8, bytes when the value is not valid UTF-8.
fn zsh_char_count(value: &[u8]) -> usize {
    match std::str::from_utf8(value) {
        Ok(text) => text.chars().count(),
        Err(_) => value.len(),
    }
}

/// `~/bin/vid-info` warm-up plus mpv through the shared IPC socket.
fn mp(targets: &[OsString]) -> i32 {
    let vid_info = join_bytes(&home(), b"/bin/vid-info");
    if is_executable(Path::new(&vid_info)) {
        let xargs_arguments: Vec<OsString> = vec![
            OsString::from("-0"),
            OsString::from("-n10"),
            OsString::from("-P"),
            OsString::from("10"),
            vid_info.clone(),
        ];
        for target in targets {
            if !Path::new(target).is_dir() {
                continue;
            }
            let find_arguments: Vec<OsString> = vec![
                OsString::from("--"),
                target.clone(),
                OsString::from("-maxdepth"),
                OsString::from("1"),
                OsString::from("-type"),
                OsString::from("f"),
                OsString::from("-print0"),
            ];
            let finder = spawn_stdout_piped(
                Site::Func("mp", 7),
                "find",
                &find_arguments,
                Stderr::Inherit,
            );
            if let Some(mut finder) = finder {
                if let Some(stdout) = finder.stdout.take() {
                    spawn_stdin_from(
                        Site::Func("mp", 7),
                        "xargs",
                        &xargs_arguments,
                        Stdio::from(stdout),
                        Stderr::Inherit,
                    );
                }
            }
        }

        let mut input = Vec::new();
        let mut files = 0;
        for target in targets {
            if Path::new(target).is_file() {
                input.extend_from_slice(target.as_bytes());
                input.push(0);
                files += 1;
            }
        }
        if files > 0 {
            spawn_stdin_bytes(
                Site::Func("mp", 18),
                "xargs",
                &xargs_arguments,
                input,
                Stderr::Inherit,
            );
        }
    }

    let tmp_dir = join_bytes(&home(), b"/tmp");
    run(
        Site::Func("mp", 22),
        "mkdir",
        &[OsString::from("-p"), OsString::from("--"), tmp_dir.clone()],
        Stdin::Inherit,
        Stdout::Inherit,
        Stderr::Inherit,
    );

    let config_home =
        var_nonempty("XDG_CONFIG_HOME").unwrap_or_else(|| join_bytes(&home(), b"/.config"));
    let ipc = join_bytes(&config_home, b"/mpv/socket");
    let log_path = join_bytes(&tmp_dir, b"/mpv.log");
    let log = match OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .open(Path::new(&log_path))
    {
        Ok(file) => file,
        Err(error) => return redirection_failure(Site::Func("mp", 24), &log_path, &error),
    };
    let stdout = match log.try_clone() {
        Ok(duplicate) => Stdout::File(duplicate),
        Err(_) => Stdout::Inherit,
    };

    let mut arguments: Vec<OsString> = Vec::new();
    let mut ipc_argument = b"--input-ipc-server=".to_vec();
    ipc_argument.extend_from_slice(ipc.as_bytes());
    arguments.push(OsString::from_vec(ipc_argument));
    arguments.push(OsString::from("--vo=gpu"));
    arguments.push(OsString::from("--"));
    arguments.extend(targets.iter().cloned());
    run(
        Site::Func("mp", 24),
        "mpv",
        &arguments,
        Stdin::Inherit,
        stdout,
        Stderr::File(log),
    )
}

fn video(arguments: &[OsString]) -> i32 {
    // `local dir="${1:-$HOME/vid/new}"` — no tilde expansion in this branch.
    let directory = match arguments.first() {
        Some(value) if !value.is_empty() => value.clone(),
        _ => join_bytes(&home(), b"/vid/new"),
    };
    let listed = capture(
        Site::Func("main", 13),
        "fd",
        &[
            OsString::from("-t"),
            OsString::from("f"),
            OsString::from("-d"),
            OsString::from("1"),
            OsString::from("."),
            directory,
        ],
        Stdin::Null,
        Stderr::Null,
    );
    let selection = capture(
        Site::Func("main", 13),
        "vicinae",
        &[
            OsString::from("dmenu"),
            OsString::from("-p"),
            OsString::from(PROMPT),
        ],
        Stdin::Bytes(listed.stdout),
        Stderr::Inherit,
    )
    .text();
    if selection.is_empty() {
        return 0;
    }
    wl_copy(Site::Func("main", 15), &selection);
    // Legacy mode keeps its hard-coded socket path.
    run(
        Site::Func("main", 16),
        "mpv",
        &[
            OsString::from("--input-ipc-server=/tmp/mpvsocket"),
            OsString::from("--vo=gpu"),
            OsString::from_vec(selection),
        ],
        Stdin::Inherit,
        Stdout::Inherit,
        Stderr::Inherit,
    )
}

fn main_pl(arguments: &[OsString]) -> i32 {
    let mut index = 0;
    let mut dmenu = false;
    if let Some(first) = arguments.first() {
        if matches!(first.as_bytes(), b"vicinae" | b"dmenu") {
            dmenu = true;
            index = 1;
        }
    }
    if arguments.get(index).map(|value| value.as_bytes()) == Some(b"video") {
        return video(&arguments[index + 1..]);
    }
    let mut maxdepth = OsString::new();
    if arguments.get(index).map(|value| value.as_bytes()) == Some(b"1st_level") {
        maxdepth = OsString::from("1");
        index += 1;
    }
    let directory = arguments.get(index).cloned().unwrap_or_default();
    if dmenu {
        pl_dmenu(&directory, &maxdepth)
    } else {
        pl_fzf(&directory, &maxdepth)
    }
}

fn volume(arguments: &[OsString]) -> i32 {
    let action = arguments
        .get(1)
        .map(|value| value.as_bytes())
        .unwrap_or(b"");
    match action {
        b"mute" => {
            let status = run(
                Site::Top(VOL_LINE),
                "vset",
                &[OsString::from("0.0")],
                Stdin::Inherit,
                Stdout::Inherit,
                Stderr::Inherit,
            );
            if status != 0 {
                run(
                    Site::Top(VOL_LINE),
                    "amixer",
                    &[
                        OsString::from("-q"),
                        OsString::from("set"),
                        OsString::from("Master"),
                        OsString::from("0"),
                        OsString::from("mute"),
                    ],
                    Stdin::Inherit,
                    Stdout::Inherit,
                    Stderr::Inherit,
                )
            } else {
                status
            }
        }
        b"unmute" => {
            let status = run(
                Site::Top(VOL_LINE + 1),
                "vset",
                &[OsString::from("1.0")],
                Stdin::Inherit,
                Stdout::Inherit,
                Stderr::Inherit,
            );
            if status != 0 {
                run(
                    Site::Top(VOL_LINE + 1),
                    "amixer",
                    &[
                        OsString::from("-q"),
                        OsString::from("set"),
                        OsString::from("Master"),
                        OsString::from("65536"),
                        OsString::from("unmute"),
                    ],
                    Stdin::Inherit,
                    Stdout::Inherit,
                    Stderr::Inherit,
                )
            } else {
                status
            }
        }
        // The inner `case` has no matching arm: status 0, no output.
        _ => 0,
    }
}

fn main() {
    let arguments = raw_args();
    if let Some(first) = arguments.first() {
        if matches!(first.as_bytes(), b"-h" | b"--help") {
            out_str(USAGE);
            return;
        }
    }

    let status = match arguments.first().map(|value| value.as_bytes()) {
        Some(b"cmd") => run(
            Site::Top(CMD_LINE),
            "playerctl",
            &arguments[1..],
            Stdin::Inherit,
            Stdout::Inherit,
            Stderr::Inherit,
        ),
        Some(b"vol") => volume(&arguments),
        _ => main_pl(&arguments),
    };
    std::process::exit(status);
}
