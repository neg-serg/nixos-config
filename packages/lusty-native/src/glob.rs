//! Minimal wildcard matcher for skip-dirs entries, plus '~' expansion.

/// Expand a leading '~' to the HOME directory (matching the Lua port).
pub fn expand_tilde(pat: &str) -> String {
    if pat == "~" {
        if let Ok(home) = std::env::var("HOME") {
            return home;
        }
        return pat.to_string();
    }
    if let Some(rest) = pat.strip_prefix("~/") {
        if let Ok(home) = std::env::var("HOME") {
            return format!("{}/{}", home.trim_end_matches('/'), rest);
        }
    }
    pat.to_string()
}

/// Matches a single path component against a pattern where '*' matches any
/// run (including empty) and '?' matches exactly one character. Matching is
/// ASCII-case-insensitive, like the Lua port's glob handling.
pub fn wildcard_match(pat: &str, name: &str) -> bool {
    wildcard_impl(pat.as_bytes(), name.as_bytes())
}

fn wildcard_impl(p: &[u8], n: &[u8]) -> bool {
    match (p.first(), n.first()) {
        (None, None) => true,
        (Some(b'*'), _) => {
            // Try zero-length match, then consume one character from the name.
            wildcard_impl(&p[1..], n) || (!n.is_empty() && wildcard_impl(p, &n[1..]))
        }
        (Some(b'?'), Some(_)) => wildcard_impl(&p[1..], &n[1..]),
        (Some(pc), Some(nc)) => pc.eq_ignore_ascii_case(nc) && wildcard_impl(&p[1..], &n[1..]),
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wildcard_star() {
        assert!(wildcard_match("*", "anything"));
        assert!(wildcard_match("pic*", "pic"));
        assert!(wildcard_match("pic*", "pic2024"));
        assert!(!wildcard_match("pic*", "apic"));
    }

    #[test]
    fn wildcard_question() {
        assert!(wildcard_match("pic?", "pic1"));
        assert!(!wildcard_match("pic?", "pic"));
        assert!(!wildcard_match("pic?", "pic12"));
    }

    #[test]
    fn wildcard_literal() {
        assert!(wildcard_match("pic", "PIC")); // case-insensitive
        assert!(!wildcard_match("pic", "pic2"));
    }
}
