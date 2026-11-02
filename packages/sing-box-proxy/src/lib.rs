#![forbid(unsafe_code)]

//! Proxy controller for the sing-box trojan-style config.
//!
//! This is a byte-level port of `packages/local-bin/bin/proxy`, which was a
//! bash script with three embedded Python programs. The port keeps the CLI,
//! the stdout/stderr split, the messages, the generated config JSON and the
//! validation behaviour; the golden fixtures in `tests/fixtures` were produced
//! by the original Python code (see `tests/reference/README.md`).
//!
//! Layout:
//! - `nodes` — node URI parsers (generator and validator variants).
//! - `config` — `build_config` and the bootstrap config patcher.
//! - `jsonout` — python-compatible JSON writer (`indent=2`, ensure_ascii).
//! - `validate` — TCP scan + e2e probe used by `refresh`.
//! - `subscriptions` — subscription fetch/filter/expand helpers.
//! - `service` — `on/off/status/gen/run` commands around systemd/sing-box.
//! - `refresh` — the `refresh` command.
//! - `shell` — small process helpers (curl/pgrep/systemctl wrappers).
//! - `output` — coloured stderr helpers and progress lines.

pub mod b64;
pub mod cli;
pub mod config;
pub mod jsonout;
pub mod nodes;
pub mod output;
pub mod paths;
pub mod random;
pub mod refresh;
pub mod secrets;
pub mod service;
pub mod shell;
pub mod subscriptions;
pub mod validate;
