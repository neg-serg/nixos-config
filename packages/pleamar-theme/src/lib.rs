//! The colour half of the pleamar theme pipeline.
//!
//! This is a behaviour-preserving port of `files/pleamar/scripts/theme/theme.sh`
//! and `theme-extract.awk`: the same CLI, the same wallpaper resolution, and the
//! same generated `~/.config/pleamar/theme.plm`, byte for byte. The awk sampler
//! (accent mean, Oklab k-means, readability clamp, light detection) lives in
//! [`extract`]; the Oklab/HSL/WCAG primitives it is built from live in
//! [`color`].
//!
//! ImageMagick and jq stay external: `magick` produces the 48x48 `txt:` dump
//! exactly as the shell asked it to (so pixel values cannot drift), and jq
//! reads `--from-json` exactly as the shell did (so its string/error semantics
//! are unchanged).

#![forbid(unsafe_code)]

pub mod color;
pub mod extract;
pub mod hex;
pub mod render;
pub mod time;
