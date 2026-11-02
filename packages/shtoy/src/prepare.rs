//! Shader preparation: the byte-for-byte equivalent of the shell's grep/sed
//! block, plus the two source inspections that only produce diagnostics.
//!
//! The shell:
//! 1. marked the source for rewriting when any line matched
//!    `^[[:space:]]*#version[[:space:]]` or started with `#!`;
//! 2. prefixed `#define iFrame int(iTime * 60.0)`,
//!    `#define iTimeDelta (1.0 / 60.0)`,
//!    `#define iFrameRate 60.0` (in that order) for every one of those names
//!    that appeared anywhere but was not declared after a `uniform`, `const`
//!    or `#define` on the same line;
//! 3. when rewriting was needed, wrote the prefix followed by every line with
//!    the `#version` and `#!` lines removed (`sed` terminates the last line
//!    with a newline even when the input did not).
//!
//! `texture2D`/`texture(` and the `iChannelN` usage notes are computed from the
//! original source, not the rewritten copy.

/// Result of preparing a source for esshader.
pub struct Rewrite {
    pub needed: bool,
    /// The bytes to hand to esshader: the untouched source when `!needed`,
    /// otherwise the define prefix followed by the stripped lines.
    pub body: Vec<u8>,
}

const DEFINES: [(&str, &str); 3] = [
    ("iFrame", "#define iFrame int(iTime * 60.0)\n"),
    ("iTimeDelta", "#define iTimeDelta (1.0 / 60.0)\n"),
    ("iFrameRate", "#define iFrameRate 60.0\n"),
];

pub fn rewrite(source: &[u8]) -> Rewrite {
    let mut prefix = String::new();
    for (name, define) in DEFINES {
        if !contains(source, name.as_bytes()) {
            continue;
        }
        if is_declared(source, name.as_bytes()) {
            continue;
        }
        prefix.push_str(define);
    }

    let removes_lines =
        has_line(source, is_version_line) || has_line(source, |line| line.starts_with(b"#!"));
    let needed = !prefix.is_empty() || removes_lines;
    if !needed {
        return Rewrite {
            needed: false,
            body: source.to_vec(),
        };
    }

    let mut body = Vec::with_capacity(prefix.len() + source.len());
    body.extend_from_slice(prefix.as_bytes());
    for line in source.split_inclusive(|byte| *byte == b'\n') {
        let has_newline = line.ends_with(b"\n");
        let content = line.strip_suffix(b"\n").unwrap_or(line);
        if is_version_line(content) || content.starts_with(b"#!") {
            continue;
        }
        body.extend_from_slice(content);
        // GNU sed preserves a missing newline on the last input line.
        if has_newline {
            body.push(b'\n');
        }
    }
    Rewrite { needed: true, body }
}

/// `grep -q texture2D` plus `! grep -q 'texture('`, both case-sensitive and
/// over the whole file, exactly as the shell tested them.
pub fn auto_legacy(source: &[u8]) -> bool {
    contains(source, b"texture2D") && !contains(source, b"texture(")
}

/// `iChannel0..3` occurrences that have no `--channel`/`--keyboard` binding.
pub fn unbound_channels(source: &[u8], bound: &[u8]) -> Vec<u8> {
    (0..=3u8)
        .filter(|channel| {
            contains(source, format!("iChannel{channel}").as_bytes()) && !bound.contains(channel)
        })
        .collect()
}

fn is_version_line(line: &[u8]) -> bool {
    let mut start = 0;
    while start < line.len() && is_space(line[start]) {
        start += 1;
    }
    let rest = &line[start..];
    rest.starts_with(b"#version")
        && rest.len() > b"#version".len()
        && is_space(rest[b"#version".len()])
}

/// The shell's ERE `(uniform|const|#define)[^;]*[^A-Za-z0-9_]<name>` applied per
/// line: after any of the three tokens there is a name occurrence with no `;`
/// in between, preceded by a character that is neither alphanumeric nor `_`.
fn is_declared(source: &[u8], name: &[u8]) -> bool {
    source
        .split(|byte| *byte == b'\n')
        .any(|line| line_declares(line, name))
}

fn line_declares(line: &[u8], name: &[u8]) -> bool {
    for token in [b"uniform".as_slice(), b"const", b"#define"] {
        let mut search_from = 0;
        while let Some(offset) = find(&line[search_from..], token) {
            let token_start = search_from + offset;
            let after_token = token_start + token.len();
            // The separator character sits at `name_start - 1`, so the name can
            // start no earlier than one byte after the token.
            let mut name_start = after_token + 1;
            while name_start + name.len() <= line.len() {
                if &line[name_start..name_start + name.len()] == name
                    && !line[after_token..name_start - 1].contains(&b';')
                {
                    return true;
                }
                name_start += 1;
            }
            search_from = token_start + 1;
        }
    }
    false
}

fn has_line<F>(source: &[u8], predicate: F) -> bool
where
    F: Fn(&[u8]) -> bool,
{
    source.split(|byte| *byte == b'\n').any(predicate)
}

fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    find(haystack, needle).is_some()
}

fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() {
        return Some(0);
    }
    haystack
        .windows(needle.len())
        .position(|window| window == needle)
}

fn is_space(byte: u8) -> bool {
    matches!(byte, b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c)
}

#[cfg(test)]
mod tests {
    use super::{auto_legacy, rewrite, unbound_channels};

    #[test]
    fn untouched_sources_are_returned_byte_for_byte() {
        let source = b"void mainImage(out vec4 c, in vec2 u) {\n  c = vec4(1.0);\n}";
        let result = rewrite(source);
        assert!(!result.needed);
        assert_eq!(result.body, source);
    }

    #[test]
    fn version_lines_are_dropped_without_a_define_prefix() {
        let result = rewrite(b"#version 300 es\nvoid main() {}\n");
        assert!(result.needed);
        assert_eq!(result.body, b"void main() {}\n");
    }

    #[test]
    fn leading_whitespace_before_version_is_accepted() {
        let result = rewrite(b"  \t#version 330 core\nvoid main() {}\n");
        assert!(result.needed);
        assert_eq!(result.body, b"void main() {}\n");
    }

    #[test]
    fn version_without_a_trailing_space_is_not_a_version_line() {
        let result = rewrite(b"#version\nvoid main() {}\n");
        assert!(!result.needed);
        assert_eq!(result.body, b"#version\nvoid main() {}\n");
    }

    #[test]
    fn shebang_lines_are_dropped() {
        let result = rewrite(b"#!/usr/bin/env shader\nvoid main() {}\n");
        assert!(result.needed);
        assert_eq!(result.body, b"void main() {}\n");
    }

    #[test]
    fn define_prefix_follows_the_shell_order() {
        let source =
            b"void main() { float a = iFrame; float b = iTimeDelta; float c = iFrameRate; }\n";
        let result = rewrite(source);
        assert!(result.needed);
        let expected = concat!(
            "#define iFrame int(iTime * 60.0)\n",
            "#define iTimeDelta (1.0 / 60.0)\n",
            "#define iFrameRate 60.0\n",
            "void main() { float a = iFrame; float b = iTimeDelta; float c = iFrameRate; }\n",
        );
        assert_eq!(String::from_utf8(result.body).unwrap(), expected);
    }

    #[test]
    fn declared_names_are_not_defined_again() {
        for declaration in [
            "uniform float iFrame;\n",
            "const float iFrame = 1.0;\n",
            "#define iFrame 1.0\n",
        ] {
            let source = format!("{declaration}void main() {{ float x = iFrame; }}\n");
            let result = rewrite(source.as_bytes());
            assert!(!result.needed, "{declaration:?} should count as declared");
            assert_eq!(result.body, source.as_bytes());
        }
    }

    #[test]
    fn a_name_only_in_a_comment_still_gets_the_define() {
        let result = rewrite(b"// uses iFrame\nvoid main() {}\n");
        assert!(result.needed);
        assert!(result.body.starts_with(b"#define iFrame "));
    }

    #[test]
    fn iframerate_use_also_triggers_the_iframe_define() {
        // The shell grepped the bare substring, and "iFrameRate" contains
        // "iFrame", so the shorter define is emitted too.
        let result = rewrite(b"float r = iFrameRate;\n");
        let text = String::from_utf8(result.body).unwrap();
        assert_eq!(
            text,
            "#define iFrame int(iTime * 60.0)\n#define iFrameRate 60.0\nfloat r = iFrameRate;\n"
        );
    }

    #[test]
    fn sed_preserves_a_missing_final_newline() {
        let result = rewrite(b"#version 300 es\nvoid main() {}");
        assert_eq!(result.body, b"void main() {}");
    }

    #[test]
    fn version_plus_defines_keeps_the_prefix_first() {
        let source = b"#version 300 es\nfloat f = iFrame;\n";
        let result = rewrite(source);
        assert_eq!(
            result.body,
            b"#define iFrame int(iTime * 60.0)\nfloat f = iFrame;\n"
        );
    }

    #[test]
    fn empty_source_needs_no_rewrite() {
        let result = rewrite(b"");
        assert!(!result.needed);
        assert!(result.body.is_empty());
    }

    #[test]
    fn declaration_detection_ignores_a_semicolon_between_token_and_name() {
        // "uniform float iTime;" ends the declaration, so the later iFrame in
        // the same line is not covered by the shell's ERE.
        let source = b"uniform float iTime; float f = iFrame;\n";
        assert!(rewrite(source).body.starts_with(b"#define iFrame "));
    }

    #[test]
    fn texture2d_legacy_detection() {
        assert!(auto_legacy(b"vec4 c = texture2D(tex, uv);"));
        assert!(auto_legacy(b"// texture2D mentioned in a comment"));
        assert!(!auto_legacy(b"vec4 c = texture(tex, uv);"));
        assert!(!auto_legacy(
            b"vec4 c = texture2D(tex, uv); vec4 d = texture(tex, uv);"
        ));
        assert!(!auto_legacy(b"nothing here"));
    }

    #[test]
    fn unbound_channel_notes_follow_first_use_order() {
        let source = b"iChannel3; iChannel0; iChannel2;";
        assert_eq!(unbound_channels(source, &[]), vec![0, 2, 3]);
        assert_eq!(unbound_channels(source, &[0, 2]), vec![3]);
        assert_eq!(unbound_channels(source, &[0, 1, 2, 3]), Vec::<u8>::new());
        assert_eq!(unbound_channels(b"iChannel4", &[]), Vec::<u8>::new());
    }
}
