//! Snapshot of the process environment.
//!
//! Taking a snapshot instead of reading `std::env` from the library makes the
//! directory layout and every network mode testable without mutating the test
//! process's environment (`env::set_var` is unsound while other threads read
//! it). `main` builds it from the live process; tests build it from a map.

use std::collections::BTreeMap;
use std::env;
use std::ffi::{OsStr, OsString};

#[derive(Clone, Debug, Default)]
pub struct Env {
    vars: BTreeMap<OsString, OsString>,
}

impl Env {
    pub fn from_process() -> Self {
        Self {
            vars: env::vars_os().collect(),
        }
    }

    pub fn from_vars<I, K, V>(vars: I) -> Self
    where
        I: IntoIterator<Item = (K, V)>,
        K: Into<OsString>,
        V: Into<OsString>,
    {
        Self {
            vars: vars
                .into_iter()
                .map(|(key, value)| (key.into(), value.into()))
                .collect(),
        }
    }

    /// Value even when it is empty; `${VAR-default}` semantics.
    pub fn get(&self, key: &str) -> Option<&OsStr> {
        self.vars.get(OsStr::new(key)).map(OsString::as_os_str)
    }

    /// Value only when it is set and non-empty; `${VAR:-default}` semantics.
    pub fn get_nonempty(&self, key: &str) -> Option<&OsStr> {
        self.get(key).filter(|value| !value.is_empty())
    }

    pub fn get_string(&self, key: &str) -> Option<String> {
        self.get(key)
            .map(|value| value.to_string_lossy().into_owned())
    }

    pub fn get_nonempty_string(&self, key: &str) -> Option<String> {
        self.get_nonempty(key)
            .map(|value| value.to_string_lossy().into_owned())
    }
}
