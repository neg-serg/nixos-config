//! Shared pieces for the Rust ports of the `packages/local-bin` helpers.
//!
//! Every helper crate used to carry its own copy of these modules, and the
//! copies drifted apart: `env.rs` alone existed in five variants with slightly
//! different function sets. The commands only ever needed one behaviour per
//! function, so the helpers live here once and every local-bin port uses them.
//!
//! The crate deliberately has no dependencies. Python and shell compatibility
//! (argparse help layout, `json`/`orjson` float formatting, `Path`
//! normalisation, exit-status conventions) needs control over the exact bytes,
//! so the small pieces live here instead of a general-purpose crate.

#![forbid(unsafe_code)]

pub mod env;
pub mod helptext;
pub mod json;
pub mod multicall;
pub mod proc;
pub mod pyfmt;
pub mod text;
