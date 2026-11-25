//! Cache keys and the deterministic stub embedder.
//!
//! These hashes are the contract with the existing on-disk cache: the Python
//! index keys every per-file vector by
//! `sha1(f"{path}:{st_mtime_ns}:{st_size}:{signature}")`, and the signature
//! itself is the first 12 hex digits of `sha1(repr((model, layer,
//! window_seconds, windows)))`. Changing either spelling silently invalidates
//! every user's cache, so the Python formatting is reproduced in [`crate::py`].

use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::Path;

use sha1::{Digest, Sha1};
use sha3::digest::{ExtendableOutput, Update, XofReader};
use sha3::Shake128;

use crate::py::{float_repr, path_str, str_repr};

/// Lower-case hex digest of `sha1(bytes)`.
pub fn sha1_hex(bytes: &[u8]) -> String {
    let mut hasher = Sha1::new();
    Digest::update(&mut hasher, bytes);
    let digest = hasher.finalize();
    let mut out = String::with_capacity(digest.len() * 2);
    for byte in digest {
        out.push_str(&format!("{byte:02x}"));
    }
    out
}

/// Short hash of the four settings that decide the embedding values.
pub fn embed_signature(model: &str, layer: i64, window_seconds: f64, windows: i64) -> String {
    let settings = format!(
        "({}, {}, {}, {})",
        str_repr(model),
        layer,
        float_repr(window_seconds),
        windows
    );
    let digest = sha1_hex(settings.as_bytes());
    digest[..12].to_string()
}

fn stat_parts(path: &Path) -> (i64, i64) {
    match fs::metadata(path) {
        Ok(metadata) => (
            metadata.mtime() * 1_000_000_000 + metadata.mtime_nsec(),
            metadata.len() as i64,
        ),
        // The Python payload would raise here; a vanished file simply re-embeds
        // on the next pass, which is the safer behaviour for a background job.
        Err(_) => (0, 0),
    }
}

fn file_key_from_parts(path_text: &str, mtime_ns: i64, size: i64, signature: &str) -> String {
    sha1_hex(format!("{path_text}:{mtime_ns}:{size}:{signature}").as_bytes())
}

fn legacy_key_from_parts(path_text: &str, mtime_ns: i64, size: i64) -> String {
    sha1_hex(format!("{path_text}:{mtime_ns}:{size}").as_bytes())
}

/// Cache key: path + mtime + size + signature.
pub fn file_key(path: &Path, signature: &str) -> String {
    let (mtime_ns, size) = stat_parts(path);
    file_key_from_parts(&path_str(path), mtime_ns, size, signature)
}

/// Cache key used before embed signatures existed (no settings folded in).
pub fn legacy_file_key(path: &Path) -> String {
    let (mtime_ns, size) = stat_parts(path);
    legacy_key_from_parts(&path_str(path), mtime_ns, size)
}

/// Deterministic hash-based unit vector used by `--selftest`.
///
/// Python computes the values in float64 and the call sites cast to float32
/// when saving; this function keeps the same float64 pipeline (summation order
/// included) and returns those values.
pub fn stub_embed(path: &Path, dim: usize) -> Vec<f64> {
    let (_, size) = stat_parts(path);
    let name = path
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_default();
    let mut hasher = Shake128::default();
    Update::update(&mut hasher, format!("{name}:{size}").as_bytes());
    let mut reader = hasher.finalize_xof();
    let mut bytes = vec![0u8; dim];
    reader.read(&mut bytes);

    let values: Vec<f64> = bytes
        .iter()
        .map(|byte| ((*byte as f64) * 2.0 - 255.0) / 255.0)
        .collect();
    let mut squares = 0.0f64;
    for value in &values {
        squares += value * value;
    }
    let scale = if squares == 0.0 {
        1.0
    } else {
        squares.powf(0.5)
    };
    values.iter().map(|value| value / scale).collect()
}
