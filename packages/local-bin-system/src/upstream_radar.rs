//! upstream-radar: a pinned DeepSeek Harness plugin compatibility scanner.
//!
//! Port of `packages/local-bin/bin/upstream-radar` (POSIX sh). Runs
//! `upstream-radar` from npm on demand inside a private cache — the shared npm
//! cache carries root-owned files and is not writable by the user. The version
//! is pinned rather than tracking `latest`: a vetting tool must produce the
//! same verdict for the same input.
//!
//! The external argv is the original one, `env` process included:
//! `env -u NPM_CONFIG_TMP NPM_CONFIG_CACHE=… NPM_CONFIG_UPDATE_NOTIFIER=false
//! npx --yes upstream-radar@0.45.0 "$@"`.

use std::fs;
use std::process::{Command, Stdio};

use local_bin_system as sh;

const VERSION: &str = "0.45.0";

const USAGE: &str = "upstream-radar: a pinned DeepSeek Harness plugin compatibility scanner.

Runs upstream-radar from npm on demand, inside a private cache. The shared
npm cache (~/.cache/npm, exported as NPM_CONFIG_CACHE in the environment)
carries root-owned files and is not writable by the user, so a plain npx
through it fails with EACCES. The version is pinned rather than tracking
`latest`: a vetting tool must produce the same verdict for the same input.

Usage (README examples that use `owner/dsh-plugin` are placeholders; use a
real repository):
  upstream-radar scan https://github.com/omdsh-dev/dsh-mnemon --fail-on never
  upstream-radar inspect <pkg>@<version> --deep --fail-on never
  upstream-radar --help

The static commands read package and repository evidence only: they never
install dependencies, run lifecycle scripts or execute plugin code.
";

fn main() {
    let arguments = sh::args();
    if arguments.first().map(String::as_str) == Some("-h")
        || arguments.first().map(String::as_str) == Some("--help")
    {
        sh::out_str(USAGE);
        return;
    }

    let cache = format!(
        "{}/upstream-radar/npm",
        sh::env_or("XDG_CACHE_HOME", &format!("{}/.cache", sh::home()))
    );
    if let Err(error) = fs::create_dir_all(&cache) {
        sh::err_line(&format!(
            "mkdir: cannot create directory '{cache}': {error}"
        ));
        std::process::exit(1);
    }

    // NPM_CONFIG_TMP is set in this environment, but npm no longer accepts
    // `tmp` as a config key; dropping the variable keeps every run free of the
    // warning.
    let mut invocation: Vec<String> = vec![
        "-u".to_string(),
        "NPM_CONFIG_TMP".to_string(),
        format!("NPM_CONFIG_CACHE={cache}"),
        "NPM_CONFIG_UPDATE_NOTIFIER=false".to_string(),
        "npx".to_string(),
        "--yes".to_string(),
        format!("upstream-radar@{VERSION}"),
    ];
    invocation.extend(arguments.iter().cloned());
    let mut command = Command::new("env");
    command.args(&invocation);
    command
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());
    match command.status() {
        Ok(status) => std::process::exit(sh::status_code(status)),
        Err(_) => std::process::exit(127),
    }
}
