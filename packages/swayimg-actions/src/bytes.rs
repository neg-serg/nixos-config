//! Byte-preserving helpers shared by the port.
//!
//! The shell worked on raw path strings, so a filename with invalid UTF-8 (or a
//! backslash, or a space) travelled through every pipeline unchanged. The port
//! keeps paths as `Vec<u8>` and converts only at the `std::fs`/`std::process`
//! boundary, which avoids the lossy `String` conversions that would otherwise
//! change both the picker input and the messages.

use std::ffi::OsString;
use std::os::unix::ffi::OsStringExt;

pub fn os_owned(bytes: &[u8]) -> OsString {
    OsString::from_vec(bytes.to_vec())
}

/// `$base/suffix`, always with the separator: the shell spelled these paths as
/// `"$HOME/tmp"`, `"$XDG_DATA_HOME/swayimg"` and so on, even when `$HOME` was
/// empty (yielding a leading slash).
pub fn join(base: &[u8], suffix: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(base.len() + 1 + suffix.len());
    out.extend_from_slice(base);
    out.push(b'/');
    out.extend_from_slice(suffix);
    out
}

/// GNU `dirname` for the shapes the script fed it (`""`, relative names, paths
/// with trailing slashes). `dirname("")` is `"."`, which is what made a failed
/// `realpath` contribute a `"."` entry to the destination picker.
pub fn dirname(path: &[u8]) -> Vec<u8> {
    if path.is_empty() {
        return b".".to_vec();
    }
    let mut end = path.len();
    while end > 0 && path[end - 1] == b'/' {
        end -= 1;
    }
    if end == 0 {
        return b"/".to_vec();
    }
    match path[..end].iter().rposition(|&b| b == b'/') {
        None => b".".to_vec(),
        Some(index) => {
            let mut name_end = index;
            while name_end > 0 && path[name_end - 1] == b'/' {
                name_end -= 1;
            }
            if name_end == 0 {
                b"/".to_vec()
            } else {
                path[..name_end].to_vec()
            }
        }
    }
}

/// The shell's `while read -r line` loop over `printf '%s\n' "$value"`:
/// newline-delimited, an unterminated final line is not delivered (zsh's
/// `read` fails at EOF), and `IFS=$'\n\t'` trims tabs at both ends while spaces
/// are preserved.
pub fn read_lines(input: &[u8]) -> Vec<Vec<u8>> {
    let mut lines = Vec::new();
    let mut start = 0;
    for (index, &byte) in input.iter().enumerate() {
        if byte != b'\n' {
            continue;
        }
        lines.push(trim_tabs(&input[start..index]));
        start = index + 1;
    }
    // A final fragment without a newline is dropped: `read` reports EOF before
    // the loop body sees it. Every producer in the script terminates its last
    // line, so this only matters for malformed input.
    lines
}

fn trim_tabs(bytes: &[u8]) -> Vec<u8> {
    let mut start = 0;
    let mut end = bytes.len();
    while start < end && bytes[start] == b'\t' {
        start += 1;
    }
    while end > start && bytes[end - 1] == b'\t' {
        end -= 1;
    }
    bytes[start..end].to_vec()
}

/// Lines of a captured command's stdout: a trailing newline does not add an
/// empty line. Used for `zoxide query -l` and for realpath output.
pub fn output_lines(input: &[u8]) -> Vec<Vec<u8>> {
    if input.is_empty() {
        return Vec::new();
    }
    let mut lines: Vec<Vec<u8>> = input.split(|&b| b == b'\n').map(<[u8]>::to_vec).collect();
    if input.ends_with(b"\n") {
        lines.pop();
    }
    lines
}

pub fn strip_trailing_newlines(mut bytes: Vec<u8>) -> Vec<u8> {
    while bytes.last() == Some(&b'\n') {
        bytes.pop();
    }
    bytes
}

pub fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    if needle.is_empty() {
        return true;
    }
    haystack
        .windows(needle.len())
        .any(|window| window == needle)
}

/// `sed "s:^$HOME:~:"` from the script: replace the leading `$HOME` with `~`.
/// An empty HOME matches the empty prefix (sed's `^`), so every line gains a
/// `~` — kept for exactness, though the variable is never empty in practice.
pub fn home_rewrite(line: &[u8], home: &[u8]) -> Vec<u8> {
    if let Some(rest) = line.strip_prefix(home) {
        let mut out = Vec::with_capacity(1 + rest.len());
        out.push(b'~');
        out.extend_from_slice(rest);
        out
    } else {
        line.to_vec()
    }
}

/// `sed "s:^~:$HOME:"` from the picker's stdout: only the first character is
/// replaced, and only when it is a literal tilde.
pub fn tilde_expand(line: &[u8], home: &[u8]) -> Vec<u8> {
    if let Some(rest) = line.strip_prefix(b"~") {
        let mut out = Vec::with_capacity(home.len() + rest.len());
        out.extend_from_slice(home);
        out.extend_from_slice(rest);
        out
    } else {
        line.to_vec()
    }
}

/// Result of zsh's builtin `echo`: `newline` is false when the input contained
/// `\c`, which suppresses both the rest of the text and the trailing newline.
pub struct Echoed {
    pub data: Vec<u8>,
    pub newline: bool,
}

/// zsh's `echo` escape processing. The script used it for the unknown-action
/// diagnostic (`echo "Unknown action: $action" >&2`) and for the wallpaper list
/// (`echo "$file" >> ...`), so a filename containing `\n` really did split the
/// list entry in two and `\c` really did swallow the newline. Unknown escapes
/// keep their backslash (`\q` stays `\q`).
pub fn zsh_echo(input: &[u8]) -> Echoed {
    let mut data = Vec::with_capacity(input.len());
    let mut index = 0;
    while index < input.len() {
        let byte = input[index];
        if byte != b'\\' {
            data.push(byte);
            index += 1;
            continue;
        }
        index += 1;
        if index == input.len() {
            data.push(b'\\');
            break;
        }
        match input[index] {
            b'c' => {
                return Echoed {
                    data,
                    newline: false,
                }
            }
            b'a' => {
                data.push(0x07);
                index += 1;
            }
            b'b' => {
                data.push(0x08);
                index += 1;
            }
            b'e' => {
                data.push(0x1b);
                index += 1;
            }
            b'f' => {
                data.push(0x0c);
                index += 1;
            }
            b'n' => {
                data.push(b'\n');
                index += 1;
            }
            b'r' => {
                data.push(b'\r');
                index += 1;
            }
            b't' => {
                data.push(b'\t');
                index += 1;
            }
            b'v' => {
                data.push(0x0b);
                index += 1;
            }
            b'\\' => {
                data.push(b'\\');
                index += 1;
            }
            b'0' => {
                index += 1;
                let mut value: u32 = 0;
                let mut digits = 0;
                while digits < 3 && index < input.len() && (b'0'..=b'7').contains(&input[index]) {
                    value = value * 8 + u32::from(input[index] - b'0');
                    index += 1;
                    digits += 1;
                }
                data.push((value & 0xff) as u8);
            }
            b'x' => {
                index += 1;
                if let Some((value, used)) = parse_hex(&input[index..], 2) {
                    data.push((value & 0xff) as u8);
                    index += used;
                } else {
                    data.extend_from_slice(b"\\x");
                }
            }
            b'u' => {
                index += 1;
                if let Some((value, used)) = parse_hex(&input[index..], 4) {
                    push_codepoint(&mut data, value);
                    index += used;
                } else {
                    data.extend_from_slice(b"\\u");
                }
            }
            b'U' => {
                index += 1;
                if let Some((value, used)) = parse_hex(&input[index..], 8) {
                    push_codepoint(&mut data, value);
                    index += used;
                } else {
                    data.extend_from_slice(b"\\U");
                }
            }
            other => {
                data.push(b'\\');
                data.push(other);
                index += 1;
            }
        }
    }
    Echoed {
        data,
        newline: true,
    }
}

fn push_codepoint(data: &mut Vec<u8>, value: u32) {
    let ch = char::from_u32(value).unwrap_or('\u{fffd}');
    let mut buffer = [0u8; 4];
    data.extend_from_slice(ch.encode_utf8(&mut buffer).as_bytes());
}

fn parse_hex(input: &[u8], max_digits: usize) -> Option<(u32, usize)> {
    let mut value: u32 = 0;
    let mut used = 0;
    while used < max_digits && used < input.len() {
        let digit = match input[used] {
            b'0'..=b'9' => u32::from(input[used] - b'0'),
            b'a'..=b'f' => u32::from(input[used] - b'a') + 10,
            b'A'..=b'F' => u32::from(input[used] - b'A') + 10,
            _ => break,
        };
        value = value * 16 + digit;
        used += 1;
    }
    if used == 0 {
        None
    } else {
        Some((value, used))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dirname_matches_gnu_coreutils() {
        let cases: &[(&[u8], &[u8])] = &[
            (b"", b"."),
            (b"a", b"."),
            (b"a/b", b"a"),
            (b"a/b/", b"a"),
            (b"a//b", b"a"),
            (b"/a", b"/"),
            (b"/a/b", b"/a"),
            (b"/", b"/"),
            (b"//", b"/"),
            (b"///", b"/"),
            (b"//a", b"/"),
            (b"./a", b"."),
            (b".", b"."),
            (b"a/.", b"a"),
            (b"a/../b", b"a/.."),
        ];
        for (input, expected) in cases {
            assert_eq!(dirname(input), expected.to_vec(), "dirname({input:?})");
        }
    }

    #[test]
    fn read_lines_matches_zsh_read() {
        assert_eq!(read_lines(b"a\n"), vec![b"a".to_vec()]);
        assert_eq!(read_lines(b"\n"), vec![Vec::<u8>::new()]);
        assert_eq!(
            read_lines(b"a\n\nb\n"),
            vec![b"a".to_vec(), Vec::new(), b"b".to_vec()]
        );
        // Tab is in IFS, space is not.
        assert_eq!(read_lines(b"\tx y\t\n"), vec![b"x y".to_vec()]);
        // No terminating newline: zsh read returns EOF, the body does not run.
        assert_eq!(read_lines(b"tail"), Vec::<Vec<u8>>::new());
    }

    #[test]
    fn echo_escapes_match_zsh_builtin() {
        assert_eq!(zsh_echo(b"a\\nb").data, b"a\nb");
        assert_eq!(zsh_echo(b"x\\ty").data, b"x\ty");
        assert_eq!(zsh_echo(b"x\\qy").data, b"x\\qy");
        assert_eq!(zsh_echo(b"x\\0101y").data, b"xAy");
        assert_eq!(zsh_echo(b"x\\x41y").data, b"xAy");
        assert_eq!(zsh_echo(b"x\\u0041y").data, b"xAy");
        let stopped = zsh_echo(b"a\\cb");
        assert_eq!(stopped.data, b"a");
        assert!(!stopped.newline);
    }

    #[test]
    fn home_rewrites_only_the_prefix() {
        assert_eq!(home_rewrite(b"/home/neg/pic", b"/home/neg"), b"~/pic");
        assert_eq!(home_rewrite(b"/mnt/one/x", b"/home/neg"), b"/mnt/one/x");
        assert_eq!(tilde_expand(b"~/pic", b"/home/neg"), b"/home/neg/pic");
        assert_eq!(tilde_expand(b"/abs", b"/home/neg"), b"/abs");
    }
}
