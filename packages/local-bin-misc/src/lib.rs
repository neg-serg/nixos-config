//! Shared runtime for the Rust ports of `packages/local-bin/bin`.
//!
//! The ports keep the observable behaviour of the shell originals: the same
//! argument handling, usage text, stdout/stderr split, exit codes, environment
//! defaults, stdin redirection and subprocess argv. Shell builtins and text
//! processing (case globs, `${VAR:-default}`, command substitution, `paste`)
//! are native here; every external program is still spawned with the original
//! arguments, and commands the originals `exec` are still exec'd so signal and
//! status handling stay identical.
//!
//! `v` has one addition: `LOCAL_BIN_MISC_V_SOCKET` overrides the hard-coded
//! `/tmp/nvim.sock` path, so a caller can point it elsewhere; production
//! behaviour is unchanged when unset.

#![forbid(unsafe_code)]

pub use local_bin_core::env::*;

// The commands are modules of this crate; `src/main.rs` dispatches on argv[0].
pub mod any;
pub mod pb;
pub mod renoise_pwj;
pub mod sclang_pwj;
pub mod v;
