//! Rust port of `packages/local-bin/bin/nb`.
//!
//! Updates `~/notes` (pull, refresh `music/list`, commit and push when
//! something changed). `git`, `mkdir`, `find`, `sort`, `date` and `zk` stay
//! subprocesses with the original argv; the branch/line arithmetic
//! (`git status --short -b | wc -l | tr -d '[:space:]'`) is native. The shell
//! original has no `set -e`: every failure except the redirect that creates
//! `music/list` is tolerated, so the port ignores the same statuses.

use std::ffi::OsStr;
use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::path::Path;
use std::process::{Command, Stdio};

use local_bin_audio::env;
use local_bin_audio::helptext::NB_HELP;
use local_bin_audio::proc::{Cmd, Sink};
use local_bin_audio::text;

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);
    let first = arguments
        .next()
        .map(|value| env::os_bytes(&value).to_vec())
        .unwrap_or_default();

    if first == b"-h" || first == b"--help" {
        env::err_str(NB_HELP);
        return;
    }

    let home = env::var_or_empty("HOME");
    let repo = join(&home, b"/notes");

    // `need git` warns and keeps going.
    if !env::which(b"git") {
        env::err_str("nb: missing git\n");
    }

    // `git -C "$repo" pull || true`
    let _ = Cmd::new("git")
        .arg("-C")
        .arg_bytes(&repo)
        .arg("pull")
        .diag(&program, 20)
        .run();

    // `mkdir -p "$repo"/music`
    let music = join(&repo, b"/music");
    let _ = Cmd::new("mkdir")
        .arg("-p")
        .arg_bytes(&music)
        .diag(&program, 21)
        .run();

    // `find "$HOME"/music -maxdepth 1 -type d | sort > "$repo"/music/list`
    write_music_list(&program, &home, &music);

    // `changed_lines="$(git -C "$repo" status --short -b | wc -l | tr -d '[:space:]')"`
    let status = Cmd::new("git")
        .arg("-C")
        .arg_bytes(&repo)
        .args(["status", "--short", "-b"])
        .stdout(Sink::Capture)
        .diag(&program, 24)
        .run();
    let newlines = status.stdout.iter().filter(|byte| **byte == b'\n').count();

    if newlines >= 2 {
        if env::which(b"zk") {
            let _ = Cmd::new("zk")
                .arg("-W")
                .arg_bytes(&repo)
                .arg("index")
                .diag(&program, 27)
                .run();
        }
        let _ = Cmd::new("git")
            .arg("-C")
            .arg_bytes(&repo)
            .args(["add", "."])
            .diag(&program, 29)
            .run();
        // `"update notes $(date '+%d-%m-%Y %H:%M:%S')"`
        let date = Cmd::new("date")
            .arg("+%d-%m-%Y %H:%M:%S")
            .stdout(Sink::Capture)
            .diag(&program, 30)
            .run();
        let mut message = b"update notes ".to_vec();
        message.extend_from_slice(text::strip_trailing_newlines(&date.stdout));
        let _ = Cmd::new("git")
            .arg("-C")
            .arg_bytes(&repo)
            .arg("commit")
            .arg("-am")
            .arg_bytes(&message)
            .diag(&program, 30)
            .run();
        let _ = Cmd::new("git")
            .arg("-C")
            .arg_bytes(&repo)
            .arg("push")
            .diag(&program, 31)
            .run();
    }
}

fn join(prefix: &[u8], suffix: &[u8]) -> Vec<u8> {
    let mut result = prefix.to_vec();
    result.extend_from_slice(suffix);
    result
}

/// `find "$HOME"/music -maxdepth 1 -type d | sort > "$repo"/music/list`.
///
/// The file is opened (created and truncated) before the pipeline starts, like
/// the shell's output redirection; when that fails the shell prints the
/// redirect diagnostic and skips the pipeline, which the port reproduces.
fn write_music_list(program: &[u8], home: &[u8], music: &[u8]) {
    let list = join(music, b"/list");
    let path = Path::new(OsStr::from_bytes(&list));
    let root = join(home, b"/music");
    let file = match fs::File::create(path) {
        Ok(file) => file,
        Err(error) => {
            // bash forks every pipeline element before the failing redirection
            // is noticed, so `find` still runs (its stdout pipe has no reader).
            env::err(&env::redirect_failure_message(program, 22, &list, &error));
            run_find(&root, Stdio::null(), program);
            return;
        }
    };
    let find = Command::new("find")
        .arg(OsStr::from_bytes(&root))
        .args(["-maxdepth", "1", "-type", "d"])
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn();
    let mut find_child = match find {
        Ok(child) => Some(child),
        Err(error) => {
            report_missing(program, 22, b"find", &error);
            None
        }
    };
    let stdin = match find_child.as_mut().and_then(|child| child.stdout.take()) {
        Some(pipe) => Stdio::from(pipe),
        None => Stdio::null(),
    };
    let sort = Command::new("sort")
        .stdin(stdin)
        .stdout(Stdio::from(file))
        .stderr(Stdio::inherit())
        .spawn();
    match sort {
        Ok(mut child) => {
            let _ = child.wait();
        }
        Err(error) => report_missing(program, 22, b"sort", &error),
    }
    if let Some(mut child) = find_child {
        let _ = child.wait();
    }
}

/// The `find` half of the pipeline, used when the redirect failed before the
/// consumer could start.
fn run_find(root: &[u8], stdout: Stdio, program: &[u8]) {
    let spawned = Command::new("find")
        .arg(OsStr::from_bytes(root))
        .args(["-maxdepth", "1", "-type", "d"])
        .stdin(Stdio::inherit())
        .stdout(stdout)
        .stderr(Stdio::inherit())
        .spawn();
    match spawned {
        Ok(mut child) => {
            let _ = child.wait();
        }
        Err(error) => report_missing(program, 22, b"find", &error),
    }
}

fn report_missing(program: &[u8], line: u32, tool: &[u8], error: &std::io::Error) {
    let message = if tool.contains(&b'/') {
        env::path_failure_message(program, line, tool, error)
    } else {
        env::not_found_message(program, line, tool)
    };
    env::err(&message);
}
