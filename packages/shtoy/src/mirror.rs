//! Sourcegraph mirror search and raw.githubusercontent.com candidate fetching.
//!
//! The shell streamed `/.api/search/stream`, kept the `data: ` payloads,
//! filtered content events that cite the shader's view URL, deduplicated by
//! repository+path, ranked by (minimum line number, extension priority, buffer
//! demotion), limited the list to eight and then downloaded candidates from
//! `raw.githubusercontent.com/<owner>/<repo>/<commit-or-HEAD>/<path>`.
//!
//! Two details of the jq expression are reproduced on purpose:
//! - a duplicate repository+path keeps the first occurrence in stream order,
//!   which is what `unique_by` does before the ranking sort;
//! - the ranking is stable for equal keys.
//!
//! The `.[]?` in `jq` iterated the elements of each `data:` array (the stream
//! sends arrays of events); `select_events` does the same and also copes with
//! object payloads. Unlike the shell, whose jq ran once per data line, the
//! events are merged before ranking here (see the crate documentation).

use std::time::Duration;

use serde_json::Value;

use crate::env::Env;
use crate::http::{Http, HttpError, Request};
use crate::PROG;

pub const DEFAULT_SOURCEGRAPH_URL: &str = "https://sourcegraph.com/.api/search/stream";
pub const DEFAULT_RAW_BASE: &str = "https://raw.githubusercontent.com";
pub const RAWS_PER_SEARCH: usize = 8;
const NO_LINE: i64 = 999;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Candidate {
    pub repository: String,
    pub commit: String,
    pub path: String,
    pub line: i64,
}

pub struct MirrorConfig<'a> {
    pub sourcegraph_url: &'a str,
    pub raw_base: &'a str,
    pub proxy: Option<&'a str>,
}

/// Parse the SSE stream (`data: <json>` lines) into content events that cite
/// the requested shader. A malformed data line makes the whole parse fail
/// (`None`), mirroring the shell where jq's non-zero exit discarded every
/// candidate.
pub fn parse_stream(stream: &[u8], id: &str) -> Option<Vec<Candidate>> {
    let reference = format!("shadertoy.com/view/{id}").to_ascii_lowercase();
    let mut candidates = Vec::new();
    for line in stream.split(|byte| *byte == b'\n') {
        let Some(payload) = line.strip_prefix(b"data: ") else {
            continue;
        };
        let text = std::str::from_utf8(payload).ok()?;
        let event: Value = serde_json::from_str(text).ok()?;
        for item in select_events(&event) {
            if item.get("type").and_then(Value::as_str) != Some("content") {
                continue;
            }
            let Some(repository) = item.get("repository").and_then(Value::as_str) else {
                continue;
            };
            let Some(path) = item.get("path").and_then(Value::as_str) else {
                continue;
            };
            if !has_shader_extension(path) {
                continue;
            }
            let (mentions, line_number) = cite_info(item, &reference);
            if !mentions {
                continue;
            }
            let commit = item
                .get("commit")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            candidates.push(Candidate {
                repository: repository.to_string(),
                commit,
                path: path.to_string(),
                line: line_number,
            });
        }
    }
    Some(candidates)
}

/// Deduplicate, rank and limit the candidates exactly as the jq tail did.
pub fn rank(candidates: Vec<Candidate>) -> Vec<Candidate> {
    let mut seen = std::collections::HashSet::new();
    let mut unique = Vec::new();
    for candidate in candidates {
        if seen.insert((candidate.repository.clone(), candidate.path.clone())) {
            unique.push(candidate);
        }
    }
    unique.sort_by(|left, right| {
        left.line
            .cmp(&right.line)
            .then_with(|| extension_priority(&left.path).cmp(&extension_priority(&right.path)))
            .then_with(|| buffer_demotion(&left.path).cmp(&buffer_demotion(&right.path)))
    });
    unique.truncate(RAWS_PER_SEARCH);
    unique
}

/// The raw.githubusercontent.com URL for a candidate, or `None` when the
/// repository is not on GitHub (the shell skipped those in its loop).
pub fn raw_url(base: &str, candidate: &Candidate) -> Option<String> {
    let repository = candidate.repository.strip_prefix("github.com/")?;
    let commit = if candidate.commit.is_empty() {
        "HEAD"
    } else {
        candidate.commit.as_str()
    };
    let path = candidate.path.replace(' ', "%20");
    Some(format!(
        "{}/{}/{}/{}",
        base.trim_end_matches('/'),
        repository,
        commit,
        path
    ))
}

/// `grep -qE '^[[:space:]]*(void|vec4)[[:space:]]+mainImage[[:space:]]*\('`.
pub fn has_main_image(source: &[u8]) -> bool {
    source
        .split(|byte| *byte == b'\n')
        .any(line_defines_main_image)
}

/// Run the whole mirror path for `id`; returns the first downloaded source that
/// declares `mainImage`. Search/partial notes and the chosen URL go to stderr,
/// as in the shell.
pub fn mirror_source(id: &str, config: &MirrorConfig<'_>, http: &dyn Http) -> Option<Vec<u8>> {
    let query = format!("count:50 content:\"shadertoy.com/view/{id}\"");
    let url = format!(
        "{}?q={}&v=V3",
        config.sourcegraph_url,
        percent_encode(&query)
    );
    let search = http.fetch(&Request {
        url: &url,
        timeout: Duration::from_secs(60),
        proxy: config.proxy,
        headers: &[("Accept", "text/event-stream")],
    });
    let stream = match search {
        Ok(body) => body,
        Err(HttpError::Transport { partial, .. }) if !partial.is_empty() => {
            eprintln!("{PROG}: note: mirror search returned partial results");
            partial
        }
        Err(_) => return None,
    };

    let candidates = parse_stream(&stream, id)?;
    for candidate in rank(candidates) {
        let Some(raw) = raw_url(config.raw_base, &candidate) else {
            continue;
        };
        match http.fetch(&Request {
            url: &raw,
            timeout: Duration::from_secs(30),
            proxy: config.proxy,
            headers: &[],
        }) {
            Ok(body) if has_main_image(&body) => {
                eprintln!("{PROG}: mirror {raw}");
                return Some(body);
            }
            _ => continue,
        }
    }
    None
}

/// Proxy for the mirror paths: `${SHTOY_PROXY-socks5h://127.0.0.1:10808}`.
/// An explicitly empty value means a direct connection.
pub fn proxy_from_env(environment: &Env) -> Option<String> {
    match environment.get("SHTOY_PROXY") {
        Some(value) if value.is_empty() => None,
        Some(value) => Some(value.to_string_lossy().into_owned()),
        None => Some("socks5h://127.0.0.1:10808".to_string()),
    }
}

fn select_events(event: &Value) -> Vec<&Value> {
    match event {
        Value::Array(items) => items.iter().collect(),
        // `.[]?` on an object produced its values; content events arrive in
        // arrays, so this only matters for progress/filters payloads.
        Value::Object(map) => map.values().collect(),
        _ => Vec::new(),
    }
}

fn cite_info(event: &Value, reference: &str) -> (bool, i64) {
    let mut mentions = false;
    let mut line_number: Option<i64> = None;
    if let Some(matches) = event.get("lineMatches").and_then(Value::as_array) {
        for line_match in matches {
            if let Some(line) = line_match.get("line").and_then(Value::as_str) {
                if line.to_ascii_lowercase().contains(reference) {
                    mentions = true;
                }
            }
            if let Some(number) = line_match.get("lineNumber").and_then(json_number) {
                line_number = Some(line_number.map_or(number, |current| current.min(number)));
            }
        }
    }
    (mentions, line_number.unwrap_or(NO_LINE))
}

fn json_number(value: &Value) -> Option<i64> {
    value
        .as_i64()
        .or_else(|| value.as_f64().map(|number| number as i64))
}

fn has_shader_extension(path: &str) -> bool {
    let lower = path.to_ascii_lowercase();
    lower.ends_with(".frag") || lower.ends_with(".fs") || lower.ends_with(".glsl")
}

fn extension_priority(path: &str) -> u8 {
    if has_shader_extension(path) {
        0
    } else {
        2
    }
}

fn buffer_demotion(path: &str) -> u8 {
    let lower = path.to_ascii_lowercase();
    if lower.contains("buffer") || lower.contains("buf") {
        1
    } else {
        0
    }
}

fn line_defines_main_image(line: &[u8]) -> bool {
    let mut start = 0;
    while start < line.len() && is_space(line[start]) {
        start += 1;
    }
    let rest = &line[start..];
    if !(rest.starts_with(b"void") || rest.starts_with(b"vec4")) {
        return false;
    }
    let rest = &rest[4..];

    let mut spaces = 0;
    while spaces < rest.len() && is_space(rest[spaces]) {
        spaces += 1;
    }
    if spaces == 0 {
        return false;
    }
    let rest = &rest[spaces..];
    let Some(rest) = rest.strip_prefix(b"mainImage".as_slice()) else {
        return false;
    };

    let mut spaces = 0;
    while spaces < rest.len() && is_space(rest[spaces]) {
        spaces += 1;
    }
    rest.get(spaces) == Some(&b'(')
}

fn is_space(byte: u8) -> bool {
    matches!(byte, b' ' | b'\t' | b'\r' | 0x0b | 0x0c)
}

fn percent_encode(text: &str) -> String {
    let mut output = String::new();
    for byte in text.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => {
                output.push(byte as char);
            }
            b' ' => output.push_str("%20"),
            _ => output.push_str(&format!("%{byte:02X}")),
        }
    }
    output
}
