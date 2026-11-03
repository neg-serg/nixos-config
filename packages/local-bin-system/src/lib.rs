//! Shared runtime for the system-level `packages/local-bin/bin` ports.
//!
//! The ports keep the observable behaviour of the shell originals: the same
//! argument handling, usage text, stdout/stderr split, exit codes, file
//! mutations and subprocess argv. Logic the originals implemented with shell
//! builtins or by parsing text (`sed`, `awk`, `grep`, `find`, JSON shaping) is
//! native here; programs that do real work (git, curl, hyprctl, journalctl,
//! logger, the clipboard and the media helpers) are still spawned with the
//! original arguments.

#![forbid(unsafe_code)]

use std::io::{self, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Output, Stdio};

/// `"$@"` as UTF-8 strings, the argv every port parses.
pub fn args() -> Vec<String> {
    std::env::args_os()
        .skip(1)
        .map(|value| value.to_string_lossy().into_owned())
        .collect()
}

/// `PROG=${0##*/}`: the name the helper was invoked as, so diagnostics work
/// through the `~/.local/bin` symlinks.
pub fn prog(fallback: &str) -> String {
    match std::env::args_os().next() {
        Some(argv0) => {
            let name = Path::new(&argv0)
                .file_name()
                .map(|value| value.to_string_lossy().into_owned())
                .unwrap_or_default();
            if name.is_empty() {
                fallback.to_string()
            } else {
                name
            }
        }
        None => fallback.to_string(),
    }
}

fn write_stream(mut stream: impl Write, bytes: &[u8]) {
    match stream.write_all(bytes) {
        Ok(()) => {}
        // A closed pipe is a SIGPIPE for a shell program; Rust ignores the
        // signal, so the port reproduces the shell's status.
        Err(error) if error.kind() == io::ErrorKind::BrokenPipe => std::process::exit(141),
        Err(_) => std::process::exit(1),
    }
}

pub fn out(bytes: &[u8]) {
    write_stream(io::stdout(), bytes);
}

pub fn out_str(text: &str) {
    out(text.as_bytes());
}

pub fn out_line(bytes: &[u8]) {
    let mut line = Vec::with_capacity(bytes.len() + 1);
    line.extend_from_slice(bytes);
    line.push(b'\n');
    out(&line);
}

pub fn out_str_line(text: &str) {
    out_line(text.as_bytes());
}

pub fn err(bytes: &[u8]) {
    write_stream(io::stderr(), bytes);
}

pub fn err_str(text: &str) {
    err(text.as_bytes());
}

pub fn err_line(message: &str) {
    let mut line = Vec::with_capacity(message.len() + 1);
    line.extend_from_slice(message.as_bytes());
    line.push(b'\n');
    err(&line);
}

/// `<prog>: <message>` on stderr, exit 1 — `_localbin.sh`'s `die`.
pub fn die(prog: &str, message: &str) -> ! {
    err_line(&format!("{prog}: {message}"));
    std::process::exit(1);
}

/// `${NAME:-default}`: unset and empty both mean "use the default".
pub fn env_nonempty(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|value| !value.is_empty())
}

pub fn env_or(name: &str, fallback: &str) -> String {
    env_nonempty(name).unwrap_or_else(|| fallback.to_string())
}

pub fn home() -> String {
    std::env::var("HOME").unwrap_or_default()
}

/// `command -v`: an executable file on `PATH`, or an explicit path.
pub fn which(program: &str) -> Option<PathBuf> {
    let path = Path::new(program);
    if program.contains('/') {
        return is_executable(path).then(|| path.to_path_buf());
    }
    let search = std::env::var_os("PATH")?;
    std::env::split_paths(&search)
        .map(|directory| {
            if directory.as_os_str().is_empty() {
                PathBuf::from(".")
            } else {
                directory
            }
        })
        .map(|directory| directory.join(program))
        .find(|candidate| is_executable(candidate))
}

pub fn is_executable(path: &Path) -> bool {
    match std::fs::metadata(path) {
        Ok(meta) => meta.is_file() && meta.permissions().mode() & 0o111 != 0,
        Err(_) => false,
    }
}

/// `need CMD`: warn on stderr and continue with status 0.
pub fn need(prog: &str, tool: &str) {
    if which(tool).is_none() {
        err_line(&format!("{prog}: missing {tool}"));
    }
}

/// `require CMD`: a missing tool is fatal.
pub fn require(prog: &str, tool: &str) {
    if which(tool).is_none() {
        die(prog, &format!("missing dependency: {tool}"));
    }
}

/// Exit code of a child the way a shell reports it (128 + signal).
pub fn status_code(status: ExitStatus) -> i32 {
    match status.code() {
        Some(code) => code,
        None => 128 + std::os::unix::process::ExitStatusExt::signal(&status).unwrap_or(1),
    }
}

pub fn command(program: &str) -> Command {
    Command::new(program)
}

/// Spawn with inherited stdio and wait; `None` when the program cannot be
/// started at all (a shell would report 127 and, with `set -e`, stop).
pub fn run_inherit(program: &str, arguments: &[&str]) -> Option<ExitStatus> {
    command(program).args(arguments).status().ok()
}

/// Run with both streams inherited except the ones redirected by the caller.
pub fn run_quiet(program: &str, arguments: &[&str]) -> Option<ExitStatus> {
    command(program)
        .args(arguments)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .ok()
}

/// Capture stdout; stderr is either inherited or dropped, matching the
/// original `2>/dev/null` markers.
pub fn capture(program: &str, arguments: &[&str], stderr_null: bool) -> Option<Output> {
    let mut invocation = command(program);
    invocation
        .args(arguments)
        .stdin(Stdio::null())
        .stdout(Stdio::piped());
    if stderr_null {
        invocation.stderr(Stdio::null());
    }
    invocation.output().ok()
}

/// `$(cmd)`: captured stdout with the trailing newlines a command
/// substitution removes.
pub fn capture_text(program: &str, arguments: &[&str], stderr_null: bool) -> Option<String> {
    capture(program, arguments, stderr_null).map(|output| {
        String::from_utf8_lossy(&output.stdout)
            .trim_end_matches('\n')
            .to_string()
    })
}

pub fn trim_trailing_newlines(text: &str) -> &str {
    text.trim_end_matches('\n')
}

/// `basename`: strip trailing slashes, then everything up to the last slash.
/// The root and the empty string are special-cased like coreutils.
pub fn basename(path: &str) -> String {
    if path.is_empty() {
        return String::new();
    }
    let trimmed = path.trim_end_matches('/');
    if trimmed.is_empty() {
        return "/".to_string();
    }
    match trimmed.rsplit_once('/') {
        Some((_, name)) => name.to_string(),
        None => trimmed.to_string(),
    }
}

/// `${var#prefix/}` used when reporting paths relative to Steam.
pub fn strip_prefix_with_slash(path: &str, prefix: &str) -> String {
    let needle = format!("{prefix}/");
    match path.strip_prefix(&needle) {
        Some(rest) => rest.to_string(),
        None => path.to_string(),
    }
}

/// jq's `@uri`: every byte outside `[A-Za-z0-9._~-]` becomes `%XX`.
pub fn percent_encode(text: &str) -> String {
    let mut encoded = String::with_capacity(text.len());
    for byte in text.as_bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                encoded.push(*byte as char)
            }
            _ => encoded.push_str(&format!("%{byte:02X}")),
        }
    }
    encoded
}

/// jq's `-r` rendering of a scalar: `null`/`false` are the values `// empty`
/// removes, strings are printed raw, numbers use jq's shortest form.
pub fn jq_alt_empty(value: &serde_json::Value) -> Option<String> {
    match value {
        serde_json::Value::Null | serde_json::Value::Bool(false) => None,
        serde_json::Value::Bool(true) => Some("true".to_string()),
        serde_json::Value::String(text) => Some(text.clone()),
        serde_json::Value::Number(number) => {
            if let Some(unsigned) = number.as_u64() {
                Some(unsigned.to_string())
            } else if let Some(signed) = number.as_i64() {
                Some(signed.to_string())
            } else {
                let float = number.as_f64().unwrap_or(0.0);
                Some(format_float(float))
            }
        }
        other => Some(other.to_string()),
    }
}

/// jq prints integral floats without the fractional part (`7.0` → `7`).
pub fn format_float(value: f64) -> String {
    if value.is_finite() && value.fract() == 0.0 {
        format!("{}", value as i64)
    } else {
        format!("{value}")
    }
}

/// jq's `-r` rendering of any value: strings raw, `null`/`false`/`true` and
/// numbers in their jq spelling, containers as compact JSON.
pub fn jq_render(value: &serde_json::Value) -> String {
    match value {
        serde_json::Value::Null => "null".to_string(),
        serde_json::Value::Bool(true) => "true".to_string(),
        serde_json::Value::Bool(false) => "false".to_string(),
        serde_json::Value::String(text) => text.clone(),
        serde_json::Value::Number(number) => {
            if let Some(unsigned) = number.as_u64() {
                unsigned.to_string()
            } else if let Some(signed) = number.as_i64() {
                signed.to_string()
            } else {
                format_float(number.as_f64().unwrap_or(0.0))
            }
        }
        other => other.to_string(),
    }
}

/// jq field access `.key`: an object yields the field or null, null yields
/// null, everything else is the "cannot index" error that makes jq produce no
/// output. The error carries no payload on purpose: jq only reports "cannot
/// index", and every caller degrades the same way.
#[allow(clippy::result_unit_err)]
pub fn jq_index(value: &serde_json::Value, key: &str) -> Result<serde_json::Value, ()> {
    match value {
        serde_json::Value::Object(object) => {
            Ok(object.get(key).cloned().unwrap_or(serde_json::Value::Null))
        }
        serde_json::Value::Null => Ok(serde_json::Value::Null),
        _ => Err(()),
    }
}

/// `.a.b.c` with jq's error semantics; `Ok(Null)` when a field is missing.
#[allow(clippy::result_unit_err)]
pub fn jq_index_chain(value: &serde_json::Value, path: &[&str]) -> Result<serde_json::Value, ()> {
    let mut current = value.clone();
    for key in path {
        current = jq_index(&current, key)?;
    }
    Ok(current)
}

/// `.[]?` on the value of `key`: arrays iterate items, objects iterate values,
/// null and scalars iterate nothing.
pub fn jq_iter_optional_field(value: &serde_json::Value, key: &str) -> Vec<serde_json::Value> {
    let Ok(field) = jq_index(value, key) else {
        return Vec::new();
    };
    match field {
        serde_json::Value::Array(items) => items,
        serde_json::Value::Object(object) => object.into_iter().map(|(_, value)| value).collect(),
        _ => Vec::new(),
    }
}

/// jq's implicit numeric conversion: a leading number, else 0.
pub fn awk_number(text: &str) -> f64 {
    let trimmed = text.trim_start();
    let mut end = 0;
    let mut seen_digit = false;
    let mut seen_point = false;
    let bytes: Vec<char> = trimmed.chars().collect();
    let mut index = 0;
    if index < bytes.len() && (bytes[index] == '+' || bytes[index] == '-') {
        index += 1;
    }
    while index < bytes.len() {
        let character = bytes[index];
        if character.is_ascii_digit() {
            seen_digit = true;
            index += 1;
        } else if character == '.' && !seen_point {
            seen_point = true;
            index += 1;
        } else {
            break;
        }
    }
    if !seen_digit {
        return 0.0;
    }
    let mut cursor = index;
    if cursor < bytes.len() && (bytes[cursor] == 'e' || bytes[cursor] == 'E') {
        let mut exponent = cursor + 1;
        if exponent < bytes.len() && (bytes[exponent] == '+' || bytes[exponent] == '-') {
            exponent += 1;
        }
        if exponent < bytes.len() && bytes[exponent].is_ascii_digit() {
            while exponent < bytes.len() && bytes[exponent].is_ascii_digit() {
                exponent += 1;
            }
            cursor = exponent;
        }
    }
    end += cursor;
    let candidate: String = bytes[..end].iter().collect();
    candidate.parse::<f64>().unwrap_or(0.0)
}

/// GNU `sort -V` comparison, enough for Vivaldi's `1.19.3` style versions:
/// digit runs compare numerically, everything else byte-wise.
pub fn version_cmp(left: &str, right: &str) -> std::cmp::Ordering {
    use std::cmp::Ordering;

    fn segments(text: &str) -> Vec<(bool, &str)> {
        let bytes = text.as_bytes();
        let mut result = Vec::new();
        let mut index = 0;
        while index < bytes.len() {
            let digit = bytes[index].is_ascii_digit();
            let mut end = index + 1;
            while end < bytes.len() && bytes[end].is_ascii_digit() == digit {
                end += 1;
            }
            result.push((digit, &text[index..end]));
            index = end;
        }
        result
    }

    fn digit_cmp(left: &str, right: &str) -> Ordering {
        let left_trimmed = left.trim_start_matches('0');
        let right_trimmed = right.trim_start_matches('0');
        let left_digits = if left_trimmed.is_empty() {
            "0"
        } else {
            left_trimmed
        };
        let right_digits = if right_trimmed.is_empty() {
            "0"
        } else {
            right_trimmed
        };
        match left_digits.len().cmp(&right_digits.len()) {
            Ordering::Equal => left_digits.cmp(right_digits),
            other => other,
        }
    }

    let left_segments = segments(left);
    let right_segments = segments(right);
    for (left_part, right_part) in left_segments.iter().zip(right_segments.iter()) {
        let ordering = match (left_part.0, right_part.0) {
            (true, true) => digit_cmp(left_part.1, right_part.1),
            (false, false) => left_part.1.as_bytes().cmp(right_part.1.as_bytes()),
            // A numeric segment sorts after a non-numeric one at the same
            // position, matching filevercmp's lexical/numeric split.
            (true, false) => Ordering::Greater,
            (false, true) => Ordering::Less,
        };
        if ordering != Ordering::Equal {
            return ordering;
        }
    }
    left_segments.len().cmp(&right_segments.len())
}

/// Escape the shader-call arguments: a quote or a backslash would break the
/// `hyprctl eval` expression, so the helper refuses them.
pub fn has_quote_or_backslash(text: &str) -> bool {
    text.contains('"') || text.contains('\\')
}

/// Read a file as UTF-8, mapping invalid input to an empty string (the ports
/// only read text files; a hard read error is `None`).
pub fn read_text(path: &Path) -> Option<String> {
    std::fs::read(path)
        .ok()
        .map(|bytes| String::from_utf8_lossy(&bytes).into_owned())
}

pub fn read_bytes(path: &Path) -> Option<Vec<u8>> {
    std::fs::read(path).ok()
}

/// Replace the first occurrence of `needle` on every line, preserving the
/// line terminators — the shape of `sed 's|needle|replacement|'`.
pub fn replace_first_per_line(content: &str, needle: &str, replacement: &str) -> String {
    if needle.is_empty() {
        return content.to_string();
    }
    let mut result = String::with_capacity(content.len());
    for (index, line) in content.split('\n').enumerate() {
        if index > 0 {
            result.push('\n');
        }
        match line.find(needle) {
            Some(position) => {
                result.push_str(&line[..position]);
                result.push_str(replacement);
                result.push_str(&line[position + needle.len()..]);
            }
            None => result.push_str(line),
        }
    }
    result
}

/// `sed 's|needle|replacement|g'`.
pub fn replace_all(content: &str, needle: &str, replacement: &str) -> String {
    content.replace(needle, replacement)
}

/// Delete every line that starts with `prefix` (`sed '/^prefix/d'`). The line
/// terminator goes with the deleted line, so the surrounding lines stay
/// adjacent.
pub fn delete_lines_starting_with(content: &str, prefix: &str) -> String {
    let mut result = String::with_capacity(content.len());
    for segment in content.split_inclusive('\n') {
        let line = segment.strip_suffix('\n').unwrap_or(segment);
        if line.starts_with(prefix) {
            continue;
        }
        result.push_str(segment);
    }
    result
}
