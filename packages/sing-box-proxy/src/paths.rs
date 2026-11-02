//! Runtime paths.
//!
//! Defaults are identical to the shell script. The `PROXY_*` environment
//! variables are an additive testing/staging hook: the shell hardcoded
//! `/run/secrets/*` and `$HOME/.config/...`, which made safe tests impossible
//! without touching the real secrets or the live config. When unset, behaviour
//! is unchanged.

use std::env;
use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct Paths {
    pub config: PathBuf,
    pub log: PathBuf,
    pub secret: PathBuf,
    pub lan_secret: PathBuf,
}

fn env_path(name: &str) -> Option<PathBuf> {
    match env::var_os(name) {
        Some(value) if !value.is_empty() => Some(PathBuf::from(value)),
        _ => None,
    }
}

impl Paths {
    pub fn from_env() -> Self {
        // The shell spelled the default as "$HOME/.config/..." literally; with
        // HOME unset that is "/.config/...", not a relative path.
        let home = env::var("HOME").unwrap_or_default();
        let config = env_path("PROXY_CONFIG").unwrap_or_else(|| {
            PathBuf::from(format!("{home}/.config/sing-box-trojan/config.json"))
        });
        let log =
            env_path("PROXY_LOG").unwrap_or_else(|| PathBuf::from("/tmp/sing-box-trojan.log"));
        let secret = env_path("PROXY_SECRET")
            .unwrap_or_else(|| PathBuf::from("/run/secrets/proxy-fallback"));
        let lan_secret =
            env_path("PROXY_LAN_SECRET").unwrap_or_else(|| PathBuf::from("/run/secrets/proxy-lan"));
        Self {
            config,
            log,
            secret,
            lan_secret,
        }
    }
}

/// Validation scratch directory: `VALIDATE_TMP` (as in the shell) wins, then
/// the port's `PROXY_VALIDATE_TMP`, then the shell default.
pub fn validate_tmp_dir() -> PathBuf {
    env_path("VALIDATE_TMP")
        .or_else(|| env_path("PROXY_VALIDATE_TMP"))
        .unwrap_or_else(|| PathBuf::from("/tmp/proxy-validate"))
}
