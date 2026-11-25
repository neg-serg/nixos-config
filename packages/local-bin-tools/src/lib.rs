//! Shared pieces for the small `$PATH` helpers in `packages/local-bin-tools`.
//!
//! The helpers used to be Python scripts; `json.rs` is the minimal reader they
//! share, and the rest of the crate is the ports themselves. The commands ship
//! as one multicall binary dispatched by `argv[0]` (see `src/main.rs`).

//! `#![forbid(unsafe_code)]` is deliberately absent: `menu-search` takes its
//! run lock with `flock(2)` through libc, so the unsafe call lives in one
//! audited place instead of an allow-attribute on the whole crate.

pub use local_bin_core::json;

// The commands are modules of this crate; `src/main.rs` dispatches on argv[0].
pub mod dsh_worktree;
pub mod fetch_covers;
pub mod gen_unbound_hosts;
pub mod menu_search;
pub mod paths;
pub mod ren;
pub mod surfingkeys_server;
pub mod window_activate;
