//! Base64 helpers with python/GNU semantics.
//!
//! `b64dec` mirrors the shell generator's `b64dec()`: pad to a multiple of
//! four, decode as base64url (which in python also accepts the standard `+`/`/`
//! alphabet because `urlsafe_b64decode` only translates `-`/`_`), decode the
//! bytes as UTF-8, and on any failure retry as plain base64 before returning an
//! empty string. `decode_base64_cli` mirrors GNU `base64 -d` as used by
//! `fetch_sub`: standard alphabet only, whitespace ignored, missing padding
//! tolerated, any other byte is an error.

use base64::engine::general_purpose::STANDARD;
use base64::Engine;

/// python's `b64dec()`.
pub fn b64dec(input: &str) -> String {
    for translate_urlsafe in [true, false] {
        if let Some(bytes) = decode_permissive(input, translate_urlsafe) {
            if let Ok(text) = String::from_utf8(bytes) {
                return text;
            }
        }
    }
    String::new()
}

/// Lenient decoder shared by `b64dec`: python's `binascii.a2b_base64` with
/// `validate=False` discards characters outside the alphabet, treats the first
/// `=` as the start of padding, and rejects a final group of length one.
fn decode_permissive(input: &str, translate_urlsafe: bool) -> Option<Vec<u8>> {
    let mut cleaned = String::new();
    for ch in input.chars() {
        let ch = if translate_urlsafe {
            match ch {
                '-' => '+',
                '_' => '/',
                other => other,
            }
        } else {
            ch
        };
        if ch.is_ascii_alphanumeric() || ch == '+' || ch == '/' {
            cleaned.push(ch);
        } else if ch == '=' {
            // Everything after padding is junk for the purpose of node URIs.
            break;
        }
        // Any other character is discarded (validate=False).
    }
    if cleaned.len() % 4 == 1 {
        return None;
    }
    let mut padded = cleaned;
    while padded.len() % 4 != 0 {
        padded.push('=');
    }
    STANDARD.decode(padded.as_bytes()).ok()
}

/// GNU `base64 -d` semantics, used to decode subscription bodies.
pub fn decode_base64_cli(input: &str) -> Option<Vec<u8>> {
    let mut cleaned = String::new();
    for ch in input.chars() {
        if ch.is_ascii_whitespace() {
            continue;
        }
        if ch.is_ascii_alphanumeric() || ch == '+' || ch == '/' {
            cleaned.push(ch);
        } else if ch == '=' {
            break;
        } else {
            // GNU base64 -d fails on any non-alphabet byte.
            return None;
        }
    }
    if cleaned.len() % 4 == 1 {
        return None;
    }
    let mut padded = cleaned;
    while padded.len() % 4 != 0 {
        padded.push('=');
    }
    STANDARD.decode(padded.as_bytes()).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_and_urlsafe() {
        assert_eq!(b64dec("aGVsbG8="), "hello");
        assert_eq!(b64dec("aGVsbG8"), "hello");
        assert_eq!(b64dec("aGVsbG8td29ybGQ"), "hello-world");
        assert_eq!(b64dec("aGVsbG8td29ybGQ="), "hello-world");
        // URL-safe alphabet is translated before the standard decoder.
        assert_eq!(b64dec("Pz4/"), "?>?");
    }

    #[test]
    fn garbage_is_empty() {
        assert_eq!(b64dec("!!!"), "");
        assert_eq!(b64dec("a"), "");
        assert_eq!(b64dec(""), "");
    }

    #[test]
    fn cli_decoder_is_strict_about_alphabet() {
        assert_eq!(decode_base64_cli("aGVs\nbG8=\n").unwrap(), b"hello");
        assert_eq!(decode_base64_cli("aGVsbG8").unwrap(), b"hello");
        assert!(decode_base64_cli("aGVsbG8-").is_none());
    }
}
