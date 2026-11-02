//! Genelec SAM control over the GLM USB adapter.
//!
//! The framing, the command builders and the guards live in [`protocol`]; `genlc`
//! (the CLI) and `glm5d` (the daemon) both build on it.

pub mod plan;
pub mod protocol;
