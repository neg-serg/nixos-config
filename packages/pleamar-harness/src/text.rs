//! Text behaviour the shell delegated to coreutils: masking the volatile parts
//! of a `describe` tree, canonicalising JSON, the drift diff, the budget table
//! and small file helpers.

use std::fs;
use std::io::Write;
use std::path::Path;
use std::process::{Command, Stdio};

use crate::proc;

/// The shell's `wc -l`: newline bytes.
pub fn count_lines(bytes: &[u8]) -> usize {
    bytes.iter().filter(|byte| **byte == b'\n').count()
}

/// `head -n N` on bytes: the first N lines, newlines included when present.
pub fn head_lines(bytes: &[u8], limit: usize) -> Vec<u8> {
    let mut seen = 0usize;
    let mut end = bytes.len();
    for (index, byte) in bytes.iter().enumerate() {
        if *byte == b'\n' {
            seen += 1;
            if seen == limit {
                end = index + 1;
                break;
            }
        }
    }
    bytes[..end].to_vec()
}

/// `tail -n N` on bytes. A trailing newline terminates the last line; it does
/// not start another one.
pub fn tail_lines(bytes: &[u8], limit: usize) -> Vec<u8> {
    if limit == 0 {
        return Vec::new();
    }
    let mut seen = 0usize;
    let mut start = 0usize;
    for index in (0..bytes.len()).rev() {
        if bytes[index] != b'\n' || index + 1 == bytes.len() {
            continue;
        }
        seen += 1;
        if seen == limit {
            start = index + 1;
            break;
        }
    }
    bytes[start..].to_vec()
}

/// True when both files exist and are byte-identical (`cmp -s`).
pub fn same_file(left: &Path, right: &Path) -> bool {
    match (fs::read(left), fs::read(right)) {
        (Ok(left), Ok(right)) => left == right,
        _ => false,
    }
}

/// The `[[:space:]]*$` part of `sed -e 's/[[:space:]]*$//'`, line by line.
pub fn strip_trailing_space(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for segment in text.split_inclusive('\n') {
        let (line, newline) = match segment.strip_suffix('\n') {
            Some(line) => (line, "\n"),
            None => (segment, ""),
        };
        out.push_str(line.trim_end_matches(is_space));
        out.push_str(newline);
    }
    out
}

fn is_space(character: char) -> bool {
    matches!(character, ' ' | '\t' | '\n' | '\r' | '\u{0b}' | '\u{0c}')
}

/// Mask the parts of a `describe` tree that follow the host between two runs:
/// the clock's minute, the playing media, the weather, the speakers' level and
/// the media capsule's geometry. One `sed` script in the original, applied per
/// line; the patterns here are the same.
pub fn mask_volatile(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for segment in text.split_inclusive('\n') {
        let (line, newline) = match segment.strip_suffix('\n') {
            Some(line) => (line, "\n"),
            None => (segment, ""),
        };
        out.push_str(&mask_line(line));
        out.push_str(newline);
    }
    out
}

fn mask_line(line: &str) -> String {
    let line = replace_clock(line);
    let line = replace_wrapped(&line, "«Media: ", '»', "«Media: …»");
    let line = replace_wrapped(&line, "«Weather ", '»', "«Weather …»");
    let line = replace_db(&line);
    replace_media_geometry(&line)
}

fn replace_clock(line: &str) -> String {
    let bytes = line.as_bytes();
    let mut out: Vec<u8> = Vec::with_capacity(bytes.len());
    let mut index = 0usize;
    while index + 5 <= bytes.len() {
        let matched = bytes[index].is_ascii_digit()
            && bytes[index + 1].is_ascii_digit()
            && bytes[index + 2] == b':'
            && bytes[index + 3].is_ascii_digit()
            && bytes[index + 4].is_ascii_digit();
        if matched {
            out.extend_from_slice(b"HH:MM");
            index += 5;
        } else {
            out.push(bytes[index]);
            index += 1;
        }
    }
    out.extend_from_slice(&bytes[index..]);
    String::from_utf8_lossy(&out).into_owned()
}

fn replace_wrapped(line: &str, prefix: &str, end: char, replacement: &str) -> String {
    let mut out = String::with_capacity(line.len());
    let mut rest = line;
    loop {
        let Some(start) = rest.find(prefix) else {
            out.push_str(rest);
            break;
        };
        out.push_str(&rest[..start]);
        let after = &rest[start + prefix.len()..];
        let Some(offset) = after.find(end) else {
            out.push_str(&rest[start..]);
            break;
        };
        out.push_str(replacement);
        rest = &after[offset + end.len_utf8()..];
    }
    out
}

fn replace_db(line: &str) -> String {
    let bytes = line.as_bytes();
    let replacement = b"\"-NN dB\"";
    let mut out: Vec<u8> = Vec::with_capacity(bytes.len());
    let mut index = 0usize;
    while index < bytes.len() {
        if bytes[index] == b'"' {
            let mut cursor = index + 1;
            if cursor < bytes.len() && bytes[cursor] == b'-' {
                cursor += 1;
            }
            let digits_start = cursor;
            while cursor < bytes.len() && bytes[cursor].is_ascii_digit() {
                cursor += 1;
            }
            if cursor > digits_start && bytes[cursor..].starts_with(b" dB\"") {
                out.extend_from_slice(replacement);
                index = cursor + 4;
                continue;
            }
        }
        out.push(bytes[index]);
        index += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn replace_media_geometry(line: &str) -> String {
    if !line.contains("Media: …") {
        return line.to_string();
    }
    let mut out = String::with_capacity(line.len());
    let mut rest = line;
    loop {
        let Some(start) = rest.find(" at ") else {
            out.push_str(rest);
            break;
        };
        match parse_geometry(&rest[start + 4..]) {
            Some(length) => {
                out.push_str(&rest[..start]);
                out.push_str(" at …,NN …×NN");
                rest = &rest[start + 4 + length..];
            }
            None => {
                out.push_str(&rest[..start + 4]);
                rest = &rest[start + 4..];
            }
        }
    }
    out
}

/// Parse `[0-9]+,[0-9]+ [0-9]+×[0-9]+` and return the consumed byte length.
fn parse_geometry(text: &str) -> Option<usize> {
    let bytes = text.as_bytes();
    let mut cursor = 0usize;
    let digits = |index: &mut usize| {
        let start = *index;
        while *index < bytes.len() && bytes[*index].is_ascii_digit() {
            *index += 1;
        }
        *index > start
    };
    if !digits(&mut cursor) {
        return None;
    }
    if bytes.get(cursor) != Some(&b',') {
        return None;
    }
    cursor += 1;
    if !digits(&mut cursor) {
        return None;
    }
    if bytes.get(cursor) != Some(&b' ') {
        return None;
    }
    cursor += 1;
    if !digits(&mut cursor) {
        return None;
    }
    if text[cursor..].starts_with('×') {
        cursor += '×'.len_utf8();
    } else {
        return None;
    }
    if !digits(&mut cursor) {
        return None;
    }
    Some(cursor)
}

/// The scripts' `canonicalize`: JSON is sorted by `jq -S` when jq is there and
/// otherwise masked as-is; plain text loses trailing whitespace. The return
/// value is the shell's pipeline status (`pipefail`): a failing `jq` returns
/// false even though the masked partial output was written, exactly like the
/// shell's redirected function.
pub fn canonicalize(
    source: &Path,
    jq: Option<&str>,
    dest: &Path,
    jq_error: Option<&Path>,
) -> std::io::Result<bool> {
    // The shell's redirections truncate the destination and jq's error file
    // before the function body runs.
    fs::write(dest, b"")?;
    if let Some(path) = jq_error {
        fs::write(path, b"")?;
    }
    let bytes = fs::read(source)?;
    let text = String::from_utf8_lossy(&bytes).into_owned();
    let json = matches!(bytes.first(), Some(b'{') | Some(b'['));
    if json {
        if let Some(jq) = jq {
            let mut command = Command::new(jq);
            command.arg("-S").arg(".").arg(source);
            command.stdout(Stdio::piped());
            match jq_error {
                Some(path) => {
                    command.stderr(Stdio::from(fs::File::create(path)?));
                }
                None => {
                    command.stderr(Stdio::null());
                }
            }
            let output = command.output()?;
            let masked = mask_volatile(&String::from_utf8_lossy(&output.stdout));
            fs::write(dest, masked)?;
            Ok(output.status.success())
        } else {
            fs::write(dest, mask_volatile(&text))?;
            Ok(true)
        }
    } else {
        let normalised = strip_trailing_space(&text);
        fs::write(dest, mask_volatile(&normalised))?;
        Ok(true)
    }
}

/// `diff -u -- OLD NEW`, stdout captured; stderr stays on the harness's stderr
/// like the shell's unredirected `diff`.
pub fn unified_diff(old: &Path, new: &Path) -> std::io::Result<String> {
    let mut command = Command::new("diff");
    command
        .arg("-u")
        .arg("--")
        .arg(old)
        .arg(new)
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit());
    let output = command.output()?;
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

/// Counts for the drift summary (`grep -c '^+[^+]'`, `'^-[^-]'`).
pub fn added_removed(diff: &str) -> (usize, usize) {
    let mut added = 0usize;
    let mut removed = 0usize;
    for line in diff.split_inclusive('\n') {
        let bytes = line.as_bytes();
        match bytes {
            [b'+', next, ..] if *next != b'+' => added += 1,
            [b'-', next, ..] if *next != b'-' => removed += 1,
            _ => {}
        }
    }
    (added, removed)
}

/// `diff -u ... | grep -E '^[-+][^-+]' | head -n 20 | sed 's/^/    /'`.
pub fn first_changed_lines(diff: &str, limit: usize) -> Vec<String> {
    diff.split_inclusive('\n')
        .filter(|line| {
            let bytes = line.as_bytes();
            matches!(bytes, [b'+' | b'-', next, ..] if *next != b'+' && *next != b'-')
        })
        .take(limit)
        .map(|line| format!("    {}", line.trim_end_matches('\n')))
        .collect()
}

/// `{ jq ...; jq ...; } | sort -u`: keep `sort` external so the collation is
/// the caller's, as it was in the shell.
pub fn sort_unique(input: &[u8]) -> std::io::Result<String> {
    let mut command = Command::new("sort");
    command
        .arg("-u")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit());
    let mut child = command.spawn()?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(input)?;
    }
    let output = child.wait_with_output()?;
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

/// Byte length as `wc -c < FILE` reported it.
pub fn file_size(path: &Path) -> Option<u64> {
    fs::metadata(path).ok().map(|metadata| metadata.len())
}

/// First byte of a file, when it has one (`head -c 1`).
pub fn first_byte(path: &Path) -> Option<u8> {
    fs::read(path).ok().and_then(|bytes| bytes.first().copied())
}

/// Trimmed stdout of a probe, ready to be printed as the shell's variable.
pub fn command_substitution(text: &str) -> String {
    proc::trim_newlines(text).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tail_keeps_the_requested_lines_and_a_lone_line() {
        assert_eq!(tail_lines(b"a\nb\nc\n", 2), b"b\nc\n");
        assert_eq!(tail_lines(b"a\n", 15), b"a\n");
        assert_eq!(tail_lines(b"a", 15), b"a");
        assert_eq!(tail_lines(b"a\nb", 1), b"b");
        assert_eq!(tail_lines(b"", 15), b"");
    }

    #[test]
    fn head_keeps_the_requested_lines() {
        assert_eq!(head_lines(b"a\nb\nc\n", 2), b"a\nb\n");
        assert_eq!(head_lines(b"a", 5), b"a");
        assert_eq!(head_lines(b"", 5), b"");
    }

    #[test]
    fn volatile_values_are_masked_per_line() {
        assert_eq!(mask_line("clock 09:51"), "clock HH:MM");
        assert_eq!(mask_line("«Media: Track»"), "«Media: …»");
        assert_eq!(
            mask_line("«Media: Track» at 1,2 3×4"),
            "«Media: …» at …,NN …×NN"
        );
        assert_eq!(mask_line("«Weather +5 °C»"), "«Weather …»");
        assert_eq!(mask_line("volume \"-50 dB\""), "volume \"-NN dB\"");
        assert_eq!(mask_line("level 5 dB"), "level 5 dB");
    }

    #[test]
    fn trailing_space_is_stripped_before_masking() {
        let text = strip_trailing_space("tree   \nclock 09:51  \n");
        assert_eq!(text, "tree\nclock 09:51\n");
        assert_eq!(mask_volatile(&text), "tree\nclock HH:MM\n");
    }

    #[test]
    fn diff_stats_ignore_the_file_headers() {
        let diff = "--- a\n+++ b\n@@ -1 +1 @@\n-old\n+new\n+extra\n";
        assert_eq!(added_removed(diff), (2, 1));
        assert_eq!(
            first_changed_lines(diff, 20),
            vec![
                "    -old".to_string(),
                "    +new".to_string(),
                "    +extra".to_string()
            ]
        );
    }
}
