//! Rust port of `packages/local-bin/bin/renoise-osc-config`.
//!
//! Pins Renoise's OSC server to UDP port 9002 in
//! `~/.config/Renoise/V3.5.4/Config.xml` while Renoise is closed, keeping a
//! `.renoise-osc.bak` backup on first use. The heredoc `python3` rewriter is
//! native: the file is decoded as UTF-8, universal newlines are applied exactly
//! like Python's text mode, and each `<Tag>.*?</Tag>` is replaced once without
//! crossing a newline. `pgrep` and `cp` stay subprocesses with the original
//! argv.

use std::ffi::OsStr;
use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::path::Path;

use local_bin_audio::env;
use local_bin_audio::proc::{Cmd, Sink};
use local_bin_audio::text;

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);
    let port = env::var_or("RENOISE_OSC_PORT", b"9002");
    let home = env::var_or_empty("HOME");

    let mut cfg = home;
    cfg.extend_from_slice(b"/.config/Renoise/V3.5.4/Config.xml");

    // pgrep -x renoise >/dev/null 2>&1: a missing pgrep is silent.
    let running = Cmd::new("pgrep")
        .arg("-x")
        .arg("renoise")
        .stdout(Sink::Null)
        .stderr(Sink::Null)
        .diag(&program, 14)
        .run();
    if running.code == 0 {
        env::err_str("renoise is running — close it first, then re-run\n");
        std::process::exit(1);
    }

    if !Path::new(OsStr::from_bytes(&cfg)).is_file() {
        let mut message = b"Config.xml not found: ".to_vec();
        message.extend_from_slice(&cfg);
        message.push(b'\n');
        env::err(&message);
        std::process::exit(1);
    }

    // `grep -q '<OscServerEnabled>true</OscServerEnabled>'` (an unreadable file
    // behaves like a missing match: the note is printed, then cp fails).
    let contents = fs::read(Path::new(OsStr::from_bytes(&cfg)));
    let enabled = contents
        .as_ref()
        .map(|bytes| text::contains(bytes, b"<OscServerEnabled>true</OscServerEnabled>"))
        .unwrap_or(false);
    if !enabled {
        env::err_str("note: OSC server is disabled in Config.xml — enabling it\n");
    }

    let mut backup = cfg.clone();
    backup.extend_from_slice(b".renoise-osc.bak");
    if !Path::new(OsStr::from_bytes(&backup)).is_file() {
        let copied = Cmd::new("cp")
            .arg_bytes(&cfg)
            .arg_bytes(&backup)
            .diag(&program, 25)
            .run();
        if copied.code != 0 {
            std::process::exit(copied.code);
        }
    }

    let contents = match contents {
        Ok(contents) => contents,
        Err(error) => {
            let mut message = b"renoise-osc-config: cannot read ".to_vec();
            message.extend_from_slice(&cfg);
            message.extend_from_slice(b": ");
            message.extend_from_slice(env::error_text(&error).as_bytes());
            message.push(b'\n');
            env::err(&message);
            std::process::exit(1);
        }
    };
    if std::str::from_utf8(&contents).is_err() {
        // Python raised a UnicodeDecodeError traceback here; the port reports the
        // condition instead of reproducing the traceback text.
        let mut message = b"renoise-osc-config: Config.xml is not valid UTF-8: ".to_vec();
        message.extend_from_slice(&cfg);
        message.push(b'\n');
        env::err(&message);
        std::process::exit(1);
    }

    let mut rewritten = universal_newlines(contents);
    rewritten = replace_once(
        rewritten,
        b"<OscServerEnabled>",
        b"</OscServerEnabled>",
        b"<OscServerEnabled>true</OscServerEnabled>",
    );
    rewritten = replace_once(
        rewritten,
        b"<OscServerProtocol>",
        b"</OscServerProtocol>",
        b"<OscServerProtocol>Udp</OscServerProtocol>",
    );
    let mut port_tag = b"<OscServerPort>".to_vec();
    port_tag.extend_from_slice(&port);
    port_tag.extend_from_slice(b"</OscServerPort>");
    rewritten = replace_once(
        rewritten,
        b"<OscServerPort>",
        b"</OscServerPort>",
        &port_tag,
    );

    if let Err(error) = fs::write(Path::new(OsStr::from_bytes(&cfg)), &rewritten) {
        let mut message = b"renoise-osc-config: cannot write ".to_vec();
        message.extend_from_slice(&cfg);
        message.extend_from_slice(b": ");
        message.extend_from_slice(env::error_text(&error).as_bytes());
        message.push(b'\n');
        env::err(&message);
        std::process::exit(1);
    }

    let mut first = b"Config.xml: OSC enabled, protocol Udp, port ".to_vec();
    first.extend_from_slice(&port);
    first.push(b'\n');
    env::out(&first);
    let mut second = b"backup kept at: ".to_vec();
    second.extend_from_slice(&backup);
    second.push(b'\n');
    env::out(&second);
}

/// Python's `open(..., encoding="utf-8")` text mode: `\r\n` and a lone `\r`
/// both become `\n` on read, and `\n` stays `\n` on write (Linux).
fn universal_newlines(bytes: Vec<u8>) -> Vec<u8> {
    let mut result = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'\r' {
            index += 1;
            if index < bytes.len() && bytes[index] == b'\n' {
                index += 1;
            }
            result.push(b'\n');
        } else {
            result.push(bytes[index]);
            index += 1;
        }
    }
    result
}

/// `re.sub(r"<OPEN>.*?</CLOSE>", replacement, text, count=1)` where `.` does
/// not match a newline: the first opening tag and the nearest closing tag on
/// the same line are replaced, everything else is untouched.
fn replace_once(text: Vec<u8>, open: &[u8], close: &[u8], replacement: &[u8]) -> Vec<u8> {
    // The Python regex engine finds the leftmost match; an opening tag whose
    // closing tag is on another line simply does not match and the engine keeps
    // looking for a later opening tag.
    let mut search_from = 0;
    while let Some(position) = text::find(&text[search_from..], open) {
        let start = search_from + position;
        let body_start = start + open.len();
        let mut index = body_start;
        while index + close.len() <= text.len() {
            if &text[index..index + close.len()] == close {
                let mut result = Vec::with_capacity(text.len());
                result.extend_from_slice(&text[..start]);
                result.extend_from_slice(replacement);
                result.extend_from_slice(&text[index + close.len()..]);
                return result;
            }
            if text[index] == b'\n' {
                break;
            }
            index += 1;
        }
        search_from = body_start;
    }
    text
}
