//! Byte helpers shared by the three commands. Stderr and stdout are written
//! as raw bytes: paths on Unix are bytes, and the shell printed them as such.

use std::io::{self, Write};

/// The shell's `$(…)`: strip every trailing newline, nothing else.
pub fn trim_trailing_newlines(bytes: &[u8]) -> &[u8] {
    let mut end = bytes.len();
    while end > 0 && bytes[end - 1] == b'\n' {
        end -= 1;
    }
    &bytes[..end]
}

/// All occurrences of `needle` replaced literally, as bash's `${var//pat/rep}`
/// does here (the replacement is not a pattern, unlike `&` in sed).
pub fn replace_all(haystack: &[u8], needle: &[u8], replacement: &[u8]) -> Vec<u8> {
    if needle.is_empty() {
        return haystack.to_vec();
    }
    let mut output = Vec::with_capacity(haystack.len());
    let mut at = 0;
    while at < haystack.len() {
        if haystack[at..].starts_with(needle) {
            output.extend_from_slice(replacement);
            at += needle.len();
        } else {
            output.push(haystack[at]);
            at += 1;
        }
    }
    output
}

pub fn write_stdout(bytes: &[u8]) {
    let stdout = io::stdout();
    let mut out = stdout.lock();
    let _ = out.write_all(bytes).and_then(|()| out.flush());
}

pub fn write_stderr(parts: &[&[u8]]) {
    let stderr = io::stderr();
    let mut out = stderr.lock();
    for part in parts {
        let _ = out.write_all(part);
    }
    let _ = out.flush();
}
