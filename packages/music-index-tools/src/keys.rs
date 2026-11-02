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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fsutil::TempDir;

    #[test]
    fn signatures_match_the_python_payload() {
        assert_eq!(embed_signature("stub/model", -2, 10.0, 3), "284f0848841d");
        assert_eq!(
            embed_signature("m-a-p/MERT-v1-95M", -1, 10.0, 3),
            "33e2f249753c"
        );
        assert_eq!(
            embed_signature("m-a-p/MERT-v1-95M", -2, 10.0, 3),
            "485ad9d419d1"
        );
        assert_eq!(embed_signature("a'b\"c", 3, 0.1, 7), "44b3a5309e9f");
        let variants = [
            embed_signature("other/model", -2, 10.0, 3),
            embed_signature("stub/model", -1, 10.0, 3),
            embed_signature("stub/model", -2, 5.0, 3),
            embed_signature("stub/model", -2, 10.0, 1),
        ];
        assert_eq!(
            variants
                .iter()
                .chain(std::iter::once(&"284f0848841d".to_string()))
                .collect::<std::collections::HashSet<_>>()
                .len(),
            5
        );
    }

    #[test]
    fn file_keys_match_the_python_formula() {
        // Values produced by the Python payload for /tmp/ref-key.flac with
        // mtime_ns=1700000000123456789, size=3 and the stub signature.
        assert_eq!(
            file_key_from_parts("/tmp/ref-key.flac", 1700000000123456789, 3, "284f0848841d"),
            "93c3136b75e977c2d4921c316c880d7c3636dbad"
        );
        assert_eq!(
            legacy_key_from_parts("/tmp/ref-key.flac", 1700000000123456789, 3),
            "4af4d9317dc895fa0fffdcf50bc824b587ab6f8a"
        );
    }

    #[test]
    fn file_key_uses_the_signature_and_stat() {
        let temp = TempDir::new("keys-test").unwrap();
        let path = temp.path().join("a.flac");
        fs::write(&path, b"abc").unwrap();
        let first = file_key(&path, "111111111111");
        let second = file_key(&path, "222222222222");
        assert_ne!(first, second);
        assert_eq!(first, file_key(&path, "111111111111"));
        // The legacy key ignores the signature, so it cannot change with it.
        assert_eq!(legacy_file_key(&path), legacy_file_key(&path));
        assert_ne!(first, legacy_file_key(&path));
    }

    #[test]
    fn stub_embed_matches_python_float64_reference() {
        // python: stub_embed('/tmp/ref-a.flac') for an empty file named ref-a.flac
        let expected = [
            -0.012827140744397022,
            -0.10444957463294718,
            0.23272098207691738,
            -0.21806139265474936,
            -0.09345488256632116,
            -0.4306254392761857,
            -0.39764136307630765,
            -0.15942303496607726,
            -0.1264389587661992,
            0.34999769745426157,
            -0.2547103662101694,
            0.2766997503434215,
            0.07146549843306912,
            0.10811447198848918,
            -0.45627972076497975,
            -0.06780060107752713,
        ];
        let temp = TempDir::new("stub-test").unwrap();
        let path = temp.path().join("ref-a.flac");
        fs::write(&path, b"").unwrap();
        let vector = stub_embed(&path, crate::STUB_DIM);
        assert_eq!(vector.len(), crate::STUB_DIM);
        for (index, (got, want)) in vector.iter().zip(expected.iter()).enumerate() {
            assert_eq!(got, want, "component {index}");
        }
        let norm: f64 = vector.iter().map(|value| value * value).sum();
        assert!((norm - 1.0).abs() < 1e-9, "norm {norm}");
        // The values the index writes are float32 casts, as in
        // np.asarray(values, dtype=np.float32).
        let float32: Vec<f32> = vector.iter().map(|value| *value as f32).collect();
        assert_eq!(float32.len(), 16);
    }

    #[test]
    fn stub_embed_for_one_byte_file_matches_python() {
        // python: stub_embed('/tmp/ref-other.wav'), one byte, name ref-other.wav
        let expected = [
            0.015866724502615268,
            0.41077186767881746,
            0.41077186767881746,
            -0.08285956129143529,
            0.18158584708548584,
            -0.4037199901220996,
            0.13222270418846055,
            0.24505274509594688,
            -0.09343737762651212,
            0.06522986739964054,
            -0.1357486429668195,
            0.4037199901220996,
            0.22742305120415215,
            0.30146776554969,
            -0.07228174495635845,
            0.19921554097728056,
        ];
        let temp = TempDir::new("stub-test").unwrap();
        let path = temp.path().join("ref-other.wav");
        fs::write(&path, b"x").unwrap();
        let vector = stub_embed(&path, crate::STUB_DIM);
        for (index, (got, want)) in vector.iter().zip(expected.iter()).enumerate() {
            assert_eq!(got, want, "component {index}");
        }
    }
}
