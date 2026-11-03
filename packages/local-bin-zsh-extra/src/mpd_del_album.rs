//! Rust port of `packages/local-bin/bin/mpd_del_album`.
//!
//! Reads the current track from mpc, derives its album directory, asks for
//! confirmation on stdin and moves `/one/music/<album>` to `~/trash/music/`.
//! The original's cancel branch calls `warn`, which is not a zsh builtin: the
//! diagnostic is `...: command not found: warn`, and the trailing `unset`
//! still leaves the script with status 0. Both quirks are preserved.
//!
//! mpc and mv stay subprocesses with the original argv; `head -1` and the perl
//! last-slash substitution are native.

#![forbid(unsafe_code)]

use std::ffi::OsString;
use std::io::BufRead;
use std::os::unix::ffi::{OsStrExt, OsStringExt};

use local_bin_zsh_extra::{
    capture, err, first_line, out, prog, raw_args, report_spawn_failure, run, StdioMode,
};

const BASE: &str = "/one/music";

fn main() {
    let args = raw_args();
    if let Some(first) = args.first() {
        if first == "-h" || first == "--help" {
            let mut usage = b"Usage: ".to_vec();
            usage.extend_from_slice(&prog());
            usage.extend_from_slice(b" [ARTIST]\n");
            usage.extend_from_slice(
                b"Remove current album (as detected by mpc) by moving its directory to ~/trash/music/.\n",
            );
            out(&usage);
            return;
        }
    }

    // The original joins "$@" with the first IFS character (newline) into
    // mpd_del_album_artist and only uses it in a commented-out block. When the
    // argument is present the mpc artist query is skipped.
    if args.is_empty() {
        query_mpc("%artist%", &site(19));
    }

    let album = album_directory(&query_mpc("%file%", &site(23)));

    let mut prompt = b"Remove:\n \x1b[38;5;30m".to_vec();
    prompt.extend_from_slice(&album);
    prompt.extend_from_slice(b"\x1b[m ? [y/N] ");
    out(&prompt);

    let answer = read_answer();
    if answer != b"y" {
        let mut diagnostic = std::env::args_os()
            .next()
            .unwrap_or_default()
            .as_bytes()
            .to_vec();
        diagnostic.extend_from_slice(b":29: command not found: warn\n");
        err(&diagnostic);
        // `unset -v mpd_del_album_artist` is the last command and succeeds.
        return;
    }

    let mut source = Vec::with_capacity(BASE.len() + 1 + album.len());
    source.extend_from_slice(BASE.as_bytes());
    source.push(b'/');
    source.extend_from_slice(&album);

    let mut destination = std::env::var_os("HOME").unwrap_or_default().into_vec();
    destination.extend_from_slice(b"/trash/music/");

    let status = match run(
        "mv",
        &[
            OsString::from("-v"),
            OsString::from_vec(source),
            OsString::from_vec(destination),
        ],
        StdioMode::Inherit,
        StdioMode::Inherit,
    ) {
        Ok(status) => status,
        Err(error) => report_spawn_failure(&site(31), "mv", &error, StdioMode::Inherit),
    };
    let _ = status;
    // The trailing `unset` makes the script exit 0 even when mv failed.
}

/// zsh's script diagnostic prefix: the invocation path and the source line.
fn site(line: u32) -> String {
    let argv0 = std::env::args_os().next().unwrap_or_default();
    format!("{}:{line}", argv0.to_string_lossy())
}

/// `mpc --format FORMAT | head -1`: stdout of the first line, or empty.
fn query_mpc(format: &str, site: &str) -> Vec<u8> {
    match capture(
        "mpc",
        &[OsString::from("--format"), OsString::from(format)],
        StdioMode::Inherit,
    ) {
        Ok(captured) => first_line(&captured.stdout).to_vec(),
        Err(error) => {
            report_spawn_failure(site, "mpc", &error, StdioMode::Inherit);
            Vec::new()
        }
    }
}

/// `perl -pe 's{(.+)/.+$}{$1}'`: drop the last path component. The slash that
/// matches is the last one that still has a non-empty component after it and a
/// non-empty prefix before it, so a trailing slash moves the cut one level up
/// (`Artist/Album/` becomes `Artist`).
fn album_directory(line: &[u8]) -> Vec<u8> {
    for position in (1..line.len()).rev() {
        if line[position] == b'/' && position + 1 < line.len() {
            return line[..position].to_vec();
        }
    }
    line.to_vec()
}

/// zsh `read answer` without `-r`: backslash escapes are consumed, a
/// backslash-newline continues the line, and the default IFS strips/joins the
/// surrounding whitespace. EOF is an empty answer, which cancels.
fn read_answer() -> Vec<u8> {
    let stdin = std::io::stdin();
    let mut reader = stdin.lock();
    let mut answer = Vec::new();
    loop {
        let mut line = Vec::new();
        if reader.read_until(b'\n', &mut line).unwrap_or(0) == 0 {
            break;
        }
        let newline = line.last() == Some(&b'\n');
        if newline {
            line.pop();
        }
        let mut continuation = false;
        let mut index = 0;
        while index < line.len() {
            if line[index] == b'\\' {
                match line.get(index + 1) {
                    Some(escaped) => {
                        answer.push(*escaped);
                        index += 2;
                    }
                    None if newline => {
                        // Backslash-newline: keep reading the same logical line.
                        continuation = true;
                        index += 1;
                    }
                    None => index += 1,
                }
            } else {
                answer.push(line[index]);
                index += 1;
            }
        }
        if !continuation {
            break;
        }
    }
    join_ifs_words(&answer)
}

/// The single-variable `read` result with the script's IFS (`newline`, `tab`):
/// leading/trailing tabs are removed and inner tab runs collapse to one space.
/// Spaces are not IFS here, so `  y  ` stays `  y  ` and does not confirm.
fn join_ifs_words(text: &[u8]) -> Vec<u8> {
    let mut words: Vec<&[u8]> = Vec::new();
    let mut start = None;
    for (index, byte) in text.iter().enumerate() {
        if matches!(byte, b'\t' | b'\n') {
            if let Some(begin) = start.take() {
                words.push(&text[begin..index]);
            }
        } else if start.is_none() {
            start = Some(index);
        }
    }
    if let Some(begin) = start {
        words.push(&text[begin..]);
    }
    let mut result = Vec::new();
    for (index, word) in words.iter().enumerate() {
        if index > 0 {
            result.push(b' ');
        }
        result.extend_from_slice(word);
    }
    result
}
