//! Byte-oriented text helpers that replace the shell's coreutils filters.
//!
//! The originals used `sed`, `awk`, `grep`, `sort`, `cut`, `wc`, `tr` and
//! `head` for pure text surgery. Those filters have no side effects of their
//! own, so the ports do the work here; the byte results are identical to what
//! the pipelines produced, including the `$(...)` trailing-newline rule.

/// `$(...)`: drop every trailing newline.
pub fn strip_trailing_newlines(bytes: &[u8]) -> &[u8] {
    let mut end = bytes.len();
    while end > 0 && bytes[end - 1] == b'\n' {
        end -= 1;
    }
    &bytes[..end]
}

/// The bytes before the first newline.
pub fn first_line(bytes: &[u8]) -> &[u8] {
    match bytes.iter().position(|byte| *byte == b'\n') {
        Some(position) => &bytes[..position],
        None => bytes,
    }
}

pub fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() {
        return Some(0);
    }
    haystack
        .windows(needle.len())
        .position(|window| window == needle)
}

pub fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    find(haystack, needle).is_some()
}

/// Split on the default IFS whitespace (space, tab, newline) like `read` does.
pub fn words(bytes: &[u8]) -> Vec<&[u8]> {
    let mut result = Vec::new();
    let mut start = None;
    for (index, byte) in bytes.iter().enumerate() {
        if matches!(byte, b' ' | b'\t' | b'\n') {
            if let Some(from) = start.take() {
                result.push(&bytes[from..index]);
            }
        } else if start.is_none() {
            start = Some(index);
        }
    }
    if let Some(from) = start {
        result.push(&bytes[from..]);
    }
    result
}

/// `printf '%s\n' "$VAR" | grep -c .`: lines that contain at least one byte.
pub fn count_nonempty_lines(bytes: &[u8]) -> usize {
    bytes
        .split(|byte| *byte == b'\n')
        .filter(|line| !line.is_empty())
        .count()
}

/// The lines `printf '%s\n' "$VAR"` produces.
pub fn printed_lines(bytes: &[u8]) -> Vec<&[u8]> {
    bytes.split(|byte| *byte == b'\n').collect()
}

/// awk's string-to-number conversion (`strtod` prefix), used by the volume
/// arithmetic and the `$1 != 64` mixer check.
pub fn awk_number(text: &[u8]) -> f64 {
    let text = trim_ascii(text);
    let mut index = 0;
    let mut negative = false;
    if index < text.len() && (text[index] == b'+' || text[index] == b'-') {
        negative = text[index] == b'-';
        index += 1;
    }
    let start = index;
    let mut digits = 0;
    while index < text.len() && text[index].is_ascii_digit() {
        index += 1;
        digits += 1;
    }
    if index < text.len() && text[index] == b'.' {
        index += 1;
        while index < text.len() && text[index].is_ascii_digit() {
            index += 1;
            digits += 1;
        }
    }
    if digits == 0 {
        return 0.0;
    }
    let mut end = index;
    if index < text.len() && (text[index] == b'e' || text[index] == b'E') {
        let mut exponent = index + 1;
        if exponent < text.len() && (text[exponent] == b'+' || text[exponent] == b'-') {
            exponent += 1;
        }
        let exponent_start = exponent;
        while exponent < text.len() && text[exponent].is_ascii_digit() {
            exponent += 1;
        }
        if exponent > exponent_start {
            end = exponent;
        }
    }
    let _ = start;
    match std::str::from_utf8(&text[..end])
        .ok()
        .and_then(|value| value.parse::<f64>().ok())
    {
        Some(value) => {
            if negative {
                -value
            } else {
                value
            }
        }
        None => 0.0,
    }
}

pub fn trim_ascii(bytes: &[u8]) -> &[u8] {
    let mut start = 0;
    let mut end = bytes.len();
    while start < end && matches!(bytes[start], b' ' | b'\t' | b'\n' | b'\r') {
        start += 1;
    }
    while end > start && matches!(bytes[end - 1], b' ' | b'\t' | b'\n' | b'\r') {
        end -= 1;
    }
    &bytes[start..end]
}

/// POSIX `dirname`: the last slash-delimited component is removed, redundant
/// trailing slashes are ignored, and a bare name has the directory `.`.
pub fn dirname(path: &[u8]) -> Vec<u8> {
    if path.is_empty() {
        return b".".to_vec();
    }
    let mut end = path.len();
    while end > 1 && path[end - 1] == b'/' {
        end -= 1;
    }
    let trimmed = &path[..end];
    match trimmed.iter().rposition(|byte| *byte == b'/') {
        None => b".".to_vec(),
        Some(0) => b"/".to_vec(),
        Some(position) => {
            let mut result = &trimmed[..position];
            while result.len() > 1 && result[result.len() - 1] == b'/' {
                result = &result[..result.len() - 1];
            }
            result.to_vec()
        }
    }
}

/// `sort -u` of the lines: byte ordering (the tests run under `LC_ALL=C`; the
/// real shell sorts with the locale collation).
pub fn sort_unique(lines: &[&[u8]]) -> Vec<Vec<u8>> {
    let mut owned: Vec<Vec<u8>> = lines.iter().map(|line| line.to_vec()).collect();
    owned.sort_unstable();
    owned.dedup();
    owned
}
