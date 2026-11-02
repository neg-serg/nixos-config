//! Rust port of `music_index.py` and `music_similar.py`.
//!
//! The index stays numpy-compatible on disk (float32 `.npy` files, JSONL
//! tracks, `meta.json`), and the ML embedding stays Python: every embedding
//! call is a `music-embed` subprocess (see [`embed`]) instead of an in-process
//! torch import. `--selftest` uses the same deterministic SHAKE-128 stub
//! embedder as the Python payload, so the whole pipeline is exercised without
//! torch, numpy or a model.

pub mod embed;
pub mod fsutil;
pub mod index;
pub mod jsonw;
pub mod keys;
pub mod npy;
pub mod py;
pub mod similar;
pub mod timefmt;

/// File extensions [`fsutil::scan`] treats as audio, lower-case without a dot.
pub const AUDIO_EXTS: &[&str] = &["mp3", "flac", "wav", "ogg", "opus", "m4a", "aac", "wma"];

/// Embedding settings that decide the vector values and the cache key.
pub const SETTINGS_KEYS: [&str; 4] = ["model", "layer", "window_seconds", "windows"];

/// Default model when `MUSIC_EMBED_MODEL` is unset (music_embed.DEFAULT_MODEL).
pub const DEFAULT_MODEL: &str = "m-a-p/MERT-v1-95M";

/// Default window settings (music_embed.DEFAULT_WINDOW_SECONDS / _WINDOWS).
pub const DEFAULT_WINDOW_SECONDS: f64 = 10.0;
pub const DEFAULT_WINDOWS: i64 = 3;

/// Print a progress line every N newly embedded files (music_index.PROGRESS_EVERY).
pub const PROGRESS_EVERY: usize = 25;

/// Dimension of the deterministic stub embedder (`music_index.STUB_DIM`).
pub const STUB_DIM: usize = 16;

/// `Path.home() / ".cache" / "music-index"` of the Python payloads.
pub fn default_index_dir() -> std::path::PathBuf {
    fsutil::home_dir().join(".cache").join("music-index")
}

/// `Path.home() / "music"` of the Python payloads.
pub fn default_music_dir() -> std::path::PathBuf {
    fsutil::home_dir().join("music")
}
