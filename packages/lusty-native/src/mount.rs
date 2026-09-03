//! Mount-point detection via /proc/self/mountinfo (same source as the Lua port).

use std::collections::HashSet;

/// Decode the octal escapes mountinfo uses for spaces/tabs/newlines.
fn decode(s: &str) -> String {
    s.replace("\\040", " ")
        .replace("\\011", "\t")
        .replace("\\012", "\n")
}

/// Normalize a path for comparison: collapse duplicate slashes and strip a
/// trailing slash (except for the root "/").
pub fn normalize(p: impl AsRef<str>) -> String {
    let mut out = String::with_capacity(p.as_ref().len());
    let mut prev_slash = false;
    for c in p.as_ref().chars() {
        if c == '/' {
            if !prev_slash {
                out.push(c);
            }
            prev_slash = true;
        } else {
            out.push(c);
            prev_slash = false;
        }
    }
    if out.len() > 1 {
        out = out.trim_end_matches('/').to_string();
    }
    out
}

/// The set of mount points currently present, normalized. Empty on failure.
pub fn mount_points() -> HashSet<String> {
    let mut set = HashSet::new();
    let Ok(text) = std::fs::read_to_string("/proc/self/mountinfo") else {
        return set;
    };
    for line in text.lines() {
        // Fields are separated from the optional tail by " - "; the mount
        // point is the 5th whitespace field before that separator.
        let head = line.split(" - ").next().unwrap_or(line);
        let fields: Vec<&str> = head.split_whitespace().collect();
        if fields.len() >= 5 {
            set.insert(normalize(decode(fields[4])));
        }
    }
    set
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_collapses_slashes() {
        assert_eq!(normalize("/nix/store"), "/nix/store");
        assert_eq!(normalize("/nix/store/"), "/nix/store");
        assert_eq!(normalize("//nix//store"), "/nix/store");
        assert_eq!(normalize("/"), "/");
    }

    #[test]
    fn decode_spaces() {
        assert_eq!(decode("a\\040b"), "a b");
    }
}
