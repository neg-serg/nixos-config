//! Rust port of `packages/local-bin/scripts/pass-2col`.
//!
//! Picks a gopass entry through `vicinae dmenu`, prefers an OTP code when
//! `pass otp code` has one, otherwise copies the first line of `pass show`.
//! The clipboard helpers and `pass` itself stay subprocesses with the original
//! argv; the store walk, the C-locale sort and the line surgery that the shell
//! did with find/grep/sed are native.

#![forbid(unsafe_code)]

use std::ffi::OsString;
use std::fs;
use std::io::Write;
use std::os::unix::ffi::OsStrExt;
use std::path::Path;
use std::process::{Command, Stdio};

use local_bin_scripts::env;
use local_bin_scripts::text;

fn store_entries(store: &Path) -> Vec<Vec<u8>> {
    let mut paths: Vec<Vec<u8>> = Vec::new();
    collect_gpg_files(store, &[], &mut paths);

    // find ... | grep -v ... | sed ... | LC_ALL=C sort, applied to whole
    // lines. A file name containing a newline therefore becomes several
    // entries, exactly as in the shell pipeline.
    let mut stream = Vec::new();
    for path in &paths {
        stream.extend_from_slice(path);
        stream.push(b'\n');
    }
    let mut entries: Vec<Vec<u8>> = Vec::new();
    // The stream ends with the newline of the last path; the shell pipeline has
    // no line after it. Interior empty lines (a file name containing "\n\n")
    // do become empty entries, exactly like mapfile's.
    let mut lines: Vec<&[u8]> = stream.split(|byte| *byte == b'\n').collect();
    if lines.last().map(|line| line.is_empty()).unwrap_or(false) {
        lines.pop();
    }
    for line in lines {
        if line == b".gpg-id" || line.ends_with(b"/.gpg-id") {
            continue;
        }
        let line = line.strip_prefix(b"./").unwrap_or(line);
        let entry = line.strip_suffix(b".gpg").unwrap_or(line);
        entries.push(entry.to_vec());
    }
    entries.sort();
    entries
}

fn collect_gpg_files(root: &Path, prefix: &[Vec<u8>], found: &mut Vec<Vec<u8>>) {
    let Ok(read_dir) = fs::read_dir(root) else {
        return;
    };
    for entry in read_dir.flatten() {
        let name = entry.file_name().as_bytes().to_vec();
        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        let mut components = prefix.to_vec();
        components.push(name);
        if file_type.is_dir() {
            // `find ! -path './.git/*'`: only the top-level .git is pruned.
            if components.len() == 1 && components[0] == b".git" {
                continue;
            }
            collect_gpg_files(&entry.path(), &components, found);
        } else if file_type.is_file() {
            let Some(last) = components.last() else {
                continue;
            };
            if last.ends_with(b".gpg") {
                let mut joined = Vec::new();
                for (index, component) in components.iter().enumerate() {
                    if index > 0 {
                        joined.push(b'/');
                    }
                    joined.extend_from_slice(component);
                }
                found.push(joined);
            }
        }
    }
}

fn notify(sel: &[u8], prefix: &[u8]) {
    if env::find_in_path(b"notify-send").is_none() {
        return;
    }
    let mut message = prefix.to_vec();
    message.extend_from_slice(sel);
    let _ = Command::new("notify-send")
        .arg("pass")
        .arg(std::ffi::OsStr::from_bytes(&message))
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status();
}

fn capture_pass(args: &[&std::ffi::OsStr]) -> Option<std::process::Output> {
    Command::new("pass")
        .args(args)
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .ok()
}

fn wl_copy(program: &[u8], line: u32, value: &[u8]) -> bool {
    if env::find_in_path(b"wl-copy").is_none() {
        return false;
    }
    let mut child = match Command::new("wl-copy")
        .stdin(Stdio::piped())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn()
    {
        Ok(child) => child,
        Err(_) => {
            env::command_not_found(program, line, b"wl-copy");
            std::process::exit(127);
        }
    };
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(value);
    }
    if let Ok(status) = child.wait() {
        if !status.success() {
            std::process::exit(env::status_code(status));
        }
    }
    true
}

fn pass_quiet(args: &[&std::ffi::OsStr]) -> bool {
    Command::new("pass")
        .args(args)
        .stdin(Stdio::inherit())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

fn main() {
    let mut argv = std::env::args_os();
    let argv0 = argv.next().unwrap_or_else(|| OsString::from("pass-2col"));
    let program = env::invocation_name(&argv0);

    let store: Vec<u8> = match env::var_nonempty("PASSWORD_STORE_DIR") {
        Some(value) => value,
        None => {
            let Some(home) = env::var_os("HOME") else {
                let mut message = program.clone();
                message.extend_from_slice(b": line 7: HOME: unbound variable\n");
                env::err(&message);
                std::process::exit(1);
            };
            let mut value = home.as_bytes().to_vec();
            value.extend_from_slice(b"/.local/share/pass");
            value
        }
    };
    let store_path = Path::new(std::ffi::OsStr::from_bytes(&store));
    if !store_path.is_dir() {
        return;
    }

    let entries = store_entries(store_path);
    if entries.is_empty() {
        return;
    }

    let mut input = Vec::new();
    for entry in &entries {
        input.extend_from_slice(entry);
        input.push(b'\n');
    }

    let mut vicinae = match Command::new("vicinae")
        .arg("dmenu")
        .arg("-p")
        .arg("pass ❯>")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
    {
        Ok(child) => child,
        Err(_) => {
            env::command_not_found(&program, 24, b"vicinae");
            std::process::exit(127);
        }
    };
    if let Some(mut stdin) = vicinae.stdin.take() {
        let _ = stdin.write_all(&input);
    }
    let output = match vicinae.wait_with_output() {
        Ok(output) => output,
        Err(_) => std::process::exit(1),
    };
    if !output.status.success() {
        std::process::exit(env::status_code(output.status));
    }

    let selected = text::chomp_newlines(&output.stdout).to_vec();
    let mut sel = Vec::with_capacity(selected.len());
    let mut had_nul = false;
    for byte in selected {
        if byte == 0 {
            had_nul = true;
        } else {
            sel.push(byte);
        }
    }
    if had_nul {
        let mut message = program.clone();
        message.extend_from_slice(
            b": line 24: warning: command substitution: ignored null byte in input\n",
        );
        env::err(&message);
    }
    if sel.is_empty() {
        return;
    }

    let sel_os = std::ffi::OsStr::from_bytes(&sel);
    if let Some(output) = capture_pass(&[
        std::ffi::OsStr::new("otp"),
        std::ffi::OsStr::new("code"),
        std::ffi::OsStr::new("--"),
        sel_os,
    ]) {
        if output.status.success() {
            let otp_code = text::first_line_without_crlf(text::chomp_newlines(&output.stdout));
            if !otp_code.is_empty() {
                if !wl_copy(&program, 34, &otp_code) {
                    let _ = pass_quiet(&[
                        std::ffi::OsStr::new("otp"),
                        std::ffi::OsStr::new("-c"),
                        std::ffi::OsStr::new("--"),
                        sel_os,
                    ]);
                }
                notify(&sel, b"OTP copied: ");
                return;
            }
        }
    }

    let pw = match capture_pass(&[
        std::ffi::OsStr::new("show"),
        std::ffi::OsStr::new("--"),
        sel_os,
    ]) {
        Some(output) => text::first_line_without_crlf(text::chomp_newlines(&output.stdout)),
        None => Vec::new(),
    };

    if !pw.is_empty() && pw.starts_with(b"otpauth://") {
        let copied = Command::new("pass")
            .arg("otp")
            .arg("-c")
            .arg("--")
            .arg(sel_os)
            .stdin(Stdio::inherit())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|status| status.success())
            .unwrap_or(false);
        if !copied {
            notify(&sel, b"OTP entry needs pass-otp: ");
        }
        return;
    }

    if !pw.is_empty() {
        if !wl_copy(&program, 60, &pw) {
            let _ = Command::new("pass")
                .arg("-c")
                .arg("--")
                .arg(sel_os)
                .stdin(Stdio::inherit())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status();
        }
        notify(&sel, b"Copied: ");
    }
}
