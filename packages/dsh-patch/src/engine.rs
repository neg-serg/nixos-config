//! The count-asserted exact-string patcher the dsh build scripts share.
//!
//! A replacement that does not match the expected number of times (a dsh
//! upgrade, formatting drift) aborts the build instead of shipping a
//! half-patched tree. Port of `packages/dsh/lib/patchlib.py`; the patch tables
//! live in `patches.rs`, generated from the former `patch-*.py` scripts.

/// What a replacement asserts before it is applied.
pub enum Expected {
    /// Exactly this many occurrences.
    Count(usize),
    /// Exactly once, and the error names this anchor instead of quoting it.
    Anchor(&'static str),
}

pub struct Replacement {
    pub old: &'static str,
    pub new: &'static str,
    pub expected: Expected,
}

pub struct FilePatch {
    /// Path relative to the `node_modules/@deepseek-ai` root.
    pub rel: &'static str,
    /// Log each patched file (as `announce=True` did in Python).
    pub announce: bool,
    pub replacements: &'static [Replacement],
}

/// `Python repr()` for the error text: the pattern is quoted, not dumped.
pub fn py_repr(text: &str) -> String {
    let mut out = String::with_capacity(text.len() + 2);
    out.push('\'');
    for ch in text.chars() {
        match ch {
            '\\' => out.push_str("\\\\"),
            '\'' => out.push_str("\\'"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 || (c as u32) == 0x7f => {
                out.push_str(&format!("\\x{:02x}", c as u32));
            }
            c => out.push(c),
        }
    }
    out.push('\'');
    out
}

fn first_chars(text: &str, count: usize) -> String {
    text.chars().take(count).collect()
}

/// Apply a patch set under `root`, returning the process exit code.
pub fn run_patch_set(root: &str, prog: &str, files: &[FilePatch]) -> i32 {
    for file in files {
        let path = std::path::Path::new(root).join(file.rel);
        let mut src = match std::fs::read_to_string(&path) {
            Ok(src) => src,
            Err(err) => {
                eprintln!("{prog}: {}: {err}", path.display());
                return 1;
            }
        };
        for replacement in file.replacements {
            let found = src.matches(replacement.old).count();
            let expected = match replacement.expected {
                Expected::Count(count) => count,
                Expected::Anchor(_) => 1,
            };
            if found != expected {
                match replacement.expected {
                    Expected::Anchor(label) => eprintln!(
                        "{prog}: {label} found {found} time(s) in {}, expected {expected}",
                        file.rel
                    ),
                    Expected::Count(_) => eprintln!(
                        "{prog}: {}: pattern found {found} time(s), expected {expected}: {}",
                        file.rel,
                        py_repr(&first_chars(replacement.old, 90))
                    ),
                }
                return 1;
            }
            src = src.replace(replacement.old, replacement.new);
        }
        if let Err(err) = std::fs::write(&path, &src) {
            eprintln!("{prog}: {}: {err}", path.display());
            return 1;
        }
        if file.announce {
            println!("{prog}: patched {}", file.rel);
        }
    }
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn repr_escapes_like_python() {
        assert_eq!(py_repr("a\tb\n'c'\\"), "'a\\tb\\n\\'c\\'\\\\'");
    }

    #[test]
    fn count_assertions_see_non_overlapping_matches() {
        assert_eq!("aaaa".matches("aa").count(), 2);
        assert_eq!("abc".matches("d").count(), 0);
    }
}
