//! dsh-url: print the URL the dsh web UI is serving right now.
//!
//! Port of `packages/local-bin/bin/dsh-url` (POSIX sh). The journal read is
//! still `journalctl --user -u dsh.service --no-pager`; the two extractions
//! (`grep -o 'https\?://[^ ]*' | head -n 1` and the greedy `(LAN: …)` sed) and
//! the clipboard handling keep their argv and order.

use std::io::Write;
use std::process::{Command, Stdio};

use local_bin_system as sh;

const USAGE: &str = "dsh-url: print the URL the dsh web UI is serving right now.
Usage: dsh-url [--lan|--open|--copy]
  The ?token= value is a per-process launch token, so it changes on every dsh
  restart. A browser that has exchanged it holds a signed cookie that does
  survive restarts, so this is only needed for a fresh browser/profile, a
  cleared cookie jar, or a different authority than the one that minted the
  cookie.
";

/// First `https?://` match on the line, up to the next space.
fn first_url(line: &str) -> String {
    let bytes = line.as_bytes();
    let mut best: Option<usize> = None;
    let mut index = 0;
    while index + 4 <= bytes.len() {
        if &bytes[index..index + 4] == b"http" {
            let rest = &bytes[index + 4..];
            let start_ok = rest.starts_with(b"://") || rest.starts_with(b"s://");
            if start_ok {
                best = Some(index);
                break;
            }
        }
        index += 1;
    }
    let Some(start) = best else {
        return String::new();
    };
    let end = bytes[start..]
        .iter()
        .position(|byte| *byte == b' ')
        .map(|offset| start + offset)
        .unwrap_or(bytes.len());
    String::from_utf8_lossy(&bytes[start..end]).into_owned()
}

/// `sed -n 's/.*(LAN: \([^)]*\)).*/\1/p'` for every line.
fn lan_urls(line: &str) -> Vec<String> {
    let mut matches = Vec::new();
    let mut search_end = line.len();
    while search_end > 0 {
        let Some(position) = line[..search_end].rfind("(LAN: ") else {
            break;
        };
        let rest = &line[position + "(LAN: ".len()..];
        if let Some(end) = rest.find(')') {
            matches.push(rest[..end].to_string());
            break;
        }
        // The greedy `.*` can still find an earlier `(LAN: ` before a `)`.
        search_end = position;
    }
    matches
}

fn capture_stdout(program: &str, arguments: &[&str]) -> String {
    match sh::capture(program, arguments, true) {
        Some(output) => String::from_utf8_lossy(&output.stdout)
            .trim_end_matches('\n')
            .to_string(),
        None => String::new(),
    }
}

fn copy_to_clipboard(url: &str) -> i32 {
    let (program, arguments): (&str, &[&str]) = if sh::which("wl-copy").is_some() {
        ("wl-copy", &[])
    } else if sh::which("xclip").is_some() {
        ("xclip", &["-selection", "clipboard"])
    } else {
        sh::err_line("dsh-url: neither wl-copy nor xclip is available");
        return 1;
    };
    let mut child = match Command::new(program)
        .args(arguments)
        .stdin(Stdio::piped())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn()
    {
        Ok(child) => child,
        Err(_) => return 127,
    };
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(url.as_bytes());
    }
    match child.wait() {
        Ok(status) => sh::status_code(status),
        Err(_) => 1,
    }
}

fn main() {
    if let Some(first) = sh::args().first() {
        if first == "-h" || first == "--help" {
            sh::out_str(USAGE);
            return;
        }
    }

    let journal = capture_stdout("journalctl", &["--user", "-u", "dsh.service", "--no-pager"]);
    let line = journal
        .split('\n')
        .rev()
        .find(|line| line.contains("dsh web: http"))
        .unwrap_or("")
        .to_string();
    if line.is_empty() {
        sh::err_line(
            "dsh-url: no 'dsh web:' line in the dsh.service journal — is the service running?",
        );
        std::process::exit(1);
    }

    let loopback = first_url(&line);
    let lan = lan_urls(&line).join("\n");

    let mode = std::env::args_os()
        .nth(1)
        .map(|value| value.to_string_lossy().into_owned())
        .unwrap_or_default();
    let url = match mode.as_str() {
        "" | "--open" | "--copy" => loopback,
        "--lan" => {
            if lan.is_empty() {
                sh::err_line("dsh-url: the log carries no LAN URL (loopback-only bind)");
                std::process::exit(1);
            }
            lan
        }
        other => {
            sh::err_line(&format!(
                "dsh-url: unknown option '{other}' (use --lan, --open, --copy, --help)"
            ));
            std::process::exit(2);
        }
    };

    sh::out_str_line(&url);

    match mode.as_str() {
        "--open" => {
            let status = run_open(&url);
            std::process::exit(status);
        }
        "--copy" => std::process::exit(copy_to_clipboard(&url)),
        _ => {}
    }
}

fn run_open(url: &str) -> i32 {
    match Command::new("xdg-open")
        .arg(url)
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
    {
        Ok(status) => sh::status_code(status),
        Err(_) => 127,
    }
}
