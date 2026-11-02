//! Genelec SAM control over the GLM USB adapter.
//!
//! The framing, the command builders and the guards live in [`protocol`]; the
//! `genlc` CLI, its [`daemon`] mode and the [`client`] helpers all build on it.

pub mod client;
pub mod daemon;
pub mod plan;
pub mod protocol;
