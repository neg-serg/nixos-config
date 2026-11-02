//! Shared pieces for the Rust ports of `packages/local-bin/scripts`.
//!
//! The ports keep the observable behaviour of the shell/Python originals: the
//! same argument handling, stdout/stderr split, exit codes, file writes and
//! subprocess argv. Only the logic the originals implemented in their own
//! language (directory walks, sorting, JSON shaping, formatting) is native;
//! every external program is still spawned with the original arguments.
//!
//! The crate deliberately has no dependencies. Python compatibility (argparse
//! help layout, `json`/`orjson` float formatting, `Path` normalisation) needs
//! control over the exact bytes, so the small pieces live here instead of a
//! general-purpose crate.

#![forbid(unsafe_code)]

pub mod env;
pub mod json;
pub mod pyfmt;
pub mod pypath;
pub mod text;
