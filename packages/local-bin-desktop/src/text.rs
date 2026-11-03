//! Byte-oriented text helpers that replace the shell's coreutils filters.
//!
//! The originals used `basename`, `head -1`, `cut`, `tr`, `awk` and command
//! substitution for pure text surgery. Those filters are not tools with side
//! effects, so the ports do the work here; the byte results are identical to
//! what the pipelines produced, including the `$(...)` trailing-newline rule.

/// `$(...)`: drop every trailing newline.
pub fn strip_trailing_newlines(bytes: &[u8]) -> &[u8] {
    let mut end = bytes.len();
    while end > 0 && bytes[end - 1] == b'\n' {
        end -= 1;
    }
    &bytes[..end]
}

/// `head -1 | $(...)`: the bytes before the first newline.
pub fn first_line(bytes: &[u8]) -> &[u8] {
    match bytes.iter().position(|byte| *byte == b'\n') {
        Some(position) => &bytes[..position],
        None => bytes,
    }
}

/// `basename PATH` without the trailing-slash edge cases bash also has: the
/// last component, ignoring trailing slashes unless the whole path is slashes.
pub fn basename(path: &[u8]) -> &[u8] {
    if path.is_empty() {
        return path;
    }
    let mut end = path.len();
    while end > 1 && path[end - 1] == b'/' {
        end -= 1;
    }
    let trimmed = &path[..end];
    if trimmed == b"/" {
        return trimmed;
    }
    match trimmed.iter().rposition(|byte| *byte == b'/') {
        Some(position) => &trimmed[position + 1..],
        None => trimmed,
    }
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

/// `read -r A B C REST`: first `count - 1` fields, then the remainder joined by
/// single spaces. Missing fields are empty slices.
pub fn read_fields(line: &[u8], count: usize) -> Vec<Vec<u8>> {
    let pieces = words(line);
    let mut fields: Vec<Vec<u8>> = Vec::with_capacity(count);
    for index in 0..count {
        if index + 1 == count {
            let rest = if pieces.len() > index {
                pieces[index..].join(&b' ')
            } else {
                Vec::new()
            };
            fields.push(rest);
        } else {
            fields.push(
                pieces
                    .get(index)
                    .map(|piece| piece.to_vec())
                    .unwrap_or_default(),
            );
        }
    }
    fields
}

/// `${value%/}`: remove a single trailing slash.
pub fn strip_one_trailing_slash(value: &[u8]) -> &[u8] {
    match value.strip_suffix(b"/") {
        Some(stripped) => stripped,
        None => value,
    }
}

/// `sed 's|PATTERN|REPLACEMENT|'`: replace the first literal occurrence.
pub fn replace_first(haystack: &[u8], needle: &[u8], replacement: &[u8]) -> Vec<u8> {
    if needle.is_empty() {
        return haystack.to_vec();
    }
    match find(haystack, needle) {
        Some(position) => {
            let mut result = Vec::with_capacity(haystack.len());
            result.extend_from_slice(&haystack[..position]);
            result.extend_from_slice(replacement);
            result.extend_from_slice(&haystack[position + needle.len()..]);
            result
        }
        None => haystack.to_vec(),
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

/// `tail -c N`: the last `N` bytes (fewer when the file is shorter).
pub fn tail_bytes(bytes: &[u8], count: usize) -> &[u8] {
    let from = bytes.len().saturating_sub(count);
    &bytes[from..]
}

/// `cut -c1-N` in a UTF-8 locale: the first `N` characters.
pub fn first_chars(text: &[u8], count: usize) -> Vec<u8> {
    match std::str::from_utf8(text) {
        Ok(value) => value.chars().take(count).collect::<String>().into_bytes(),
        Err(_) => text.iter().copied().take(count).collect(),
    }
}

/// `cut -c1-N` in the C locale: the first `N` bytes.
pub fn first_bytes(text: &[u8], count: usize) -> Vec<u8> {
    text.iter().copied().take(count).collect()
}

/// Whether `cut -c` counts characters or bytes: coreutils switches with the
/// effective character locale (`LC_ALL`, else `LC_CTYPE`, else `LANG`).
pub fn locale_is_utf8() -> bool {
    let value = ["LC_ALL", "LC_CTYPE", "LANG"]
        .iter()
        .find_map(|name| std::env::var_os(name).filter(|value| !value.is_empty()));
    match value {
        Some(value) => {
            let text = value.to_string_lossy().to_ascii_lowercase();
            text.contains("utf-8") || text.contains("utf8")
        }
        None => false,
    }
}

/// `tr -d '\n'`: drop every newline byte.
pub fn remove_newlines(bytes: &[u8]) -> Vec<u8> {
    bytes
        .iter()
        .copied()
        .filter(|byte| *byte != b'\n')
        .collect()
}

/// `tr '\n' ' '`: newlines become spaces.
pub fn newlines_to_spaces(bytes: &[u8]) -> Vec<u8> {
    bytes
        .iter()
        .map(|byte| if *byte == b'\n' { b' ' } else { *byte })
        .collect()
}

/// Join non-empty byte strings with a single space, as `read` does for the
/// remainder of a line.
pub fn join_words(pieces: &[&[u8]]) -> Vec<u8> {
    let mut result = Vec::new();
    for (index, piece) in pieces.iter().enumerate() {
        if index > 0 {
            result.push(b' ');
        }
        result.extend_from_slice(piece);
    }
    result
}
