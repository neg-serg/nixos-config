//! Hermetic tests for the `upstream-radar` port: the `env` argv (including
//! `-u NPM_CONFIG_TMP`), the private npm cache directory and the exit-status
//! pass-through. `env` is a fake, so `npx` never runs.

mod support;

use support::{exited, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_upstream-radar");

const ENV: &str = r#"#!/bin/sh
printf 'cmd env\n' >> "$FAKE_ARGV_LOG"
for argument in "$@"; do printf '  %s\n' "$argument" >> "$FAKE_ARGV_LOG"; done
printf 'env-out\n'
printf 'env-err\n' >&2
exit "${FAKE_ENV_CODE:-0}"
"#;

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("env", ENV);
    case
}

#[test]
fn help_prints_the_header() {
    let case = fixture("help");
    let output = case.run(&["--help"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stderr(&output), "");
    let text = stdout(&output);
    assert!(text
        .starts_with("upstream-radar: a pinned DeepSeek Harness plugin compatibility scanner.\n"));
    assert!(text.ends_with("install dependencies, run lifecycle scripts or execute plugin code.\n"));
    assert_eq!(case.argv_log(), "");
}

#[test]
fn the_pinned_env_argv_is_exact() {
    let case = fixture("argv");
    let output = case.run(&["scan", "https://example.invalid/x", "--fail-on", "never"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "env-out\n");
    assert_eq!(stderr(&output), "env-err\n");
    let expected = format!(
        "cmd env\n  -u\n  NPM_CONFIG_TMP\n  NPM_CONFIG_CACHE={}/.cache/upstream-radar/npm\n  NPM_CONFIG_UPDATE_NOTIFIER=false\n  npx\n  --yes\n  upstream-radar@0.45.0\n  scan\n  https://example.invalid/x\n  --fail-on\n  never\n",
        case.home.to_string_lossy()
    );
    assert_eq!(case.argv_log(), expected);
    assert!(case.home.join(".cache/upstream-radar/npm").is_dir());
}

#[test]
fn xdg_cache_home_is_honored() {
    let case = fixture("xdg");
    let cache = case.path("cache");
    let _ = case.run_env(&[], &[("XDG_CACHE_HOME", &cache.to_string_lossy())]);
    assert!(cache.join("upstream-radar/npm").is_dir());
    assert!(case.argv_log().contains(&format!(
        "  NPM_CONFIG_CACHE={}/upstream-radar/npm\n",
        cache.to_string_lossy()
    )));
}

#[test]
fn the_env_status_is_propagated() {
    let case = fixture("status");
    let output = case.run_env(&[], &[("FAKE_ENV_CODE", "9")]);
    assert_eq!(exited(&output), 9);
    assert_eq!(stdout(&output), "env-out\n");
}

#[test]
fn an_unwritable_cache_path_fails_like_mkdir() {
    let case = fixture("mkdir-fail");
    let blocked = case.path("blocked");
    case.write(&blocked, "not a directory");
    let output = case.run_env(
        &[],
        &[("XDG_CACHE_HOME", &blocked.join("sub").to_string_lossy())],
    );
    assert_eq!(exited(&output), 1);
    assert!(
        stderr(&output).starts_with("mkdir: cannot create directory"),
        "{}",
        stderr(&output)
    );
    assert_eq!(case.argv_log(), "");
}

#[test]
fn a_missing_env_binary_exits_127() {
    let case = fixture("no-env");
    case.remove_fake("env");
    let output = case.run(&[]);
    assert_eq!(exited(&output), 127);
}

#[test]
fn help_is_only_the_first_argument() {
    let case = fixture("help-late");
    let output = case.run(&["scan", "--help"]);
    assert_eq!(exited(&output), 0);
    assert!(case.argv_log().contains("  scan\n  --help\n"));
    assert!(!stdout(&output).starts_with("upstream-radar: a pinned"));
}
