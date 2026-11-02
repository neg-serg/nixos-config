//! Subscription fetching, filtering and fallback expansion.
//!
//! Ports `fetch_sub()` and `expand_fallback()` from the shell:
//! - fetch a URL with curl (direct, then through the running proxy if the
//!   direct body was empty);
//! - decode base64 subscription bodies when no `scheme://` line is present;
//! - keep only node lines, drop `type=xhttp`/`type=splithttp`/`plugin=`
//!   entries, shuffle and sample up to `NODE_SAMPLE` (default 400);
//! - `expand_fallback` treats `http(s)://` secret lines as subscriptions and
//!   passes everything else through, warning about empty subscriptions.

use crate::b64;
use crate::output::Ui;
use crate::random::shuffle;
use crate::shell;
use std::env;

const SCHEMES: [&str; 9] = [
    "vless",
    "vmess",
    "hysteria2",
    "hy2",
    "hysteria",
    "tuic",
    "ss",
    "trojan",
    "anytls",
];

/// True when the line begins with a supported node scheme (`^(...)://`).
pub fn starts_with_scheme(line: &str) -> bool {
    SCHEMES
        .iter()
        .any(|scheme| line.starts_with(&format!("{scheme}://")))
}

fn has_blocked_marker(line: &str) -> bool {
    ["type=xhttp", "type=splithttp", "plugin="]
        .iter()
        .any(|marker| line.contains(&format!("?{marker}")) || line.contains(&format!("&{marker}")))
}

fn curl_body(args: &[&str]) -> String {
    let owned: Vec<std::ffi::OsString> = args.iter().map(std::ffi::OsString::from).collect();
    let text = match shell::run_capture("curl", &owned, None, true) {
        Ok(output) => String::from_utf8_lossy(&output.stdout).into_owned(),
        Err(_) => String::new(),
    };
    // Command substitution strips trailing newlines.
    text.trim_end_matches('\n').to_string()
}

/// `head -"${NODE_SAMPLE:-400}"` semantics: unset/empty -> 400, invalid -> 0.
fn node_sample() -> usize {
    match env::var("NODE_SAMPLE") {
        Err(_) => 400,
        Ok(value) if value.is_empty() => 400,
        Ok(value) => value.parse().unwrap_or(0),
    }
}

/// `fetch_sub <url>`: one subscription URL -> newline-joined node lines with
/// no trailing newline (as captured by `$(...)`).
pub fn fetch_sub(url: &str) -> String {
    let mut body = curl_body(&[
        "--noproxy",
        "*",
        "-sL",
        "--connect-timeout",
        "8",
        "--max-time",
        "20",
        url,
    ]);
    if body.is_empty() && shell::pgrep("sing-box.*config.json") {
        body = curl_body(&[
            "-sL",
            "--connect-timeout",
            "8",
            "--max-time",
            "25",
            "--proxy",
            "socks5h://127.0.0.1:10808",
            url,
        ]);
    }
    if !body.split('\n').any(starts_with_scheme) {
        body = match b64::decode_base64_cli(&body) {
            Some(bytes) => String::from_utf8_lossy(&bytes).into_owned(),
            None => String::new(),
        };
    }
    let mut lines: Vec<String> = body
        .split('\n')
        .filter(|line| starts_with_scheme(line) && !has_blocked_marker(line))
        .map(|line| line.to_string())
        .collect();
    shuffle(&mut lines);
    lines.truncate(node_sample());
    lines.join("\n")
}

/// `basename <url>` (the shell used coreutils' basename, which only looks at
/// slashes; a query string stays part of the final component).
pub fn basename(url: &str) -> String {
    let trimmed = url.trim_end_matches('/');
    match trimmed.rsplit_once('/') {
        Some((_, name)) => name.to_string(),
        None => trimmed.to_string(),
    }
}

/// `expand_fallback`: SOPS fallback lines -> node list (empty lines dropped).
pub fn expand_fallback(ui: &mut Ui, secret_text: &str) -> String {
    let secret = secret_text.trim_end_matches('\n');
    let mut lines: Vec<String> = Vec::new();
    for line in secret.split('\n') {
        if line.is_empty() {
            continue;
        }
        if line.starts_with("http://") || line.starts_with("https://") {
            let data = fetch_sub(line);
            if data.is_empty() {
                ui.warn(&format!(
                    "no nodes from fallback subscription {}",
                    basename(line)
                ));
            } else {
                lines.extend(data.split('\n').map(|node| node.to_string()));
            }
        } else {
            lines.push(line.to_string());
        }
    }
    lines
        .into_iter()
        .filter(|line| !line.is_empty())
        .collect::<Vec<String>>()
        .join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn basename_matches_coreutils() {
        assert_eq!(basename("https://example.com/path/nodes.txt"), "nodes.txt");
        assert_eq!(basename("https://example.com/path/"), "path");
        assert_eq!(basename("https://example.com"), "example.com");
        assert_eq!(basename("plain-name"), "plain-name");
    }

    #[test]
    fn scheme_and_marker_filters() {
        assert!(starts_with_scheme("vless://uuid@host:443"));
        assert!(!starts_with_scheme("http://example.com/vless://x"));
        assert!(!starts_with_scheme(" vless://uuid@host:443"));
        assert!(has_blocked_marker("vless://u@h:1?security=tls&type=xhttp"));
        assert!(has_blocked_marker("vless://u@h:1?type=splithttp"));
        assert!(has_blocked_marker("ss://u@h:1?plugin=obfs-local"));
        assert!(!has_blocked_marker("vless://u@h:1?type=ws&host=x"));
    }

    #[test]
    fn expand_fallback_passes_plain_lines_and_drops_empty() {
        let mut buffer = Vec::new();
        let mut ui = Ui::new(&mut buffer, false, false);
        let expanded = expand_fallback(
            &mut ui,
            "vless://a@b.example.com:443?security=tls#A\n\n\ntrojan://pw@c.example.com:443\n",
        );
        assert_eq!(
            expanded,
            "vless://a@b.example.com:443?security=tls#A\ntrojan://pw@c.example.com:443"
        );
        assert!(buffer.is_empty());
    }
}
