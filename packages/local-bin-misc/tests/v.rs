//! Hermetic tests for the `v` port.
//!
//! Every case points LOCAL_BIN_MISC_V_SOCKET at a socket path inside the
//! per-case temporary tree; the host's `/tmp/nvim.sock` is never created,
//! inspected or removed. Fake `nc`/`nvr`/`hyprctl`/`rm`/`nvim` log argv and
//! decide success, so both the attached and the fresh-server branches run
//! without a real editor.

mod support;

use support::{exited, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_v");
const ATTACHED: &str = "\u{2197}  nvim (attached)\n";

const NC: &str = r#"#!/bin/sh
printf 'nc\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
printf '%s' "${FAKE_NC_OUT:-}"
printf '%s' "${FAKE_NC_ERR:-}" >&2
exit "${FAKE_NC_CODE:-0}"
"#;

const NVR: &str = r#"#!/bin/sh
printf 'nvr\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
printf 'nvr NVIM_APPNAME=[%s] set=%s\n' "${NVIM_APPNAME-}" "${NVIM_APPNAME+set}" >> "$FAKE_ENV_LOG"
printf '%s' "${FAKE_NVR_OUT:-}"
printf '%s' "${FAKE_NVR_ERR:-}" >&2
exit "${FAKE_NVR_CODE:-0}"
"#;

const HYPRCTL: &str = r#"#!/bin/sh
printf 'hyprctl\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
printf '%s' "${FAKE_HYPRCTL_OUT:-}"
printf '%s' "${FAKE_HYPRCTL_ERR:-}" >&2
exit "${FAKE_HYPRCTL_CODE:-0}"
"#;

const RM: &str = r#"#!/bin/sh
printf 'rm\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
exit "${FAKE_RM_CODE:-0}"
"#;

const NVIM: &str = r#"#!/bin/sh
printf 'nvim\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
printf 'nvim NVIM_APPNAME=[%s] set=%s\n' "${NVIM_APPNAME-}" "${NVIM_APPNAME+set}" >> "$FAKE_ENV_LOG"
printf '%s' "${FAKE_NVIM_OUT:-}"
printf '%s' "${FAKE_NVIM_ERR:-}" >&2
exit "${FAKE_NVIM_CODE:-0}"
"#;

fn fixture(label: &str, socket: bool) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("nc", NC);
    case.write_fake("nvr", NVR);
    case.write_fake("hyprctl", HYPRCTL);
    case.write_fake("rm", RM);
    case.write_fake("nvim", NVIM);
    if socket {
        case.write_stale_socket();
    }
    case
}

fn run(case: &Case, arguments: &[&str], nc_code: &str) -> std::process::Output {
    case.command()
        .args(arguments)
        .env("LOCAL_BIN_MISC_V_SOCKET", case.socket_path())
        .env("FAKE_NC_CODE", nc_code)
        .output()
        .expect("run v")
}

fn log_call(log: &mut String, tool: &str, arguments: &[&str]) {
    log.push_str(tool);
    log.push('\n');
    for argument in arguments {
        log.push_str(&format!("  {argument}\n"));
    }
}

fn socket(case: &Case) -> String {
    case.socket_path().to_string_lossy().into_owned()
}

fn attached_log(case: &Case, nvr_arguments: Option<&[&str]>) -> String {
    let socket = socket(case);
    let mut log = String::new();
    log_call(&mut log, "nc", &["-zU", &socket]);
    if let Some(arguments) = nvr_arguments {
        let mut full = vec!["--servername", socket.as_str(), "--remote-silent"];
        full.extend_from_slice(arguments);
        log_call(&mut log, "nvr", &full);
    }
    log_call(
        &mut log,
        "hyprctl",
        &["dispatch", "focuswindow", "class:nwim"],
    );
    log
}

fn fresh_log(case: &Case, nvim_arguments: &[&str]) -> String {
    let socket = socket(case);
    let mut log = String::new();
    log_call(&mut log, "rm", &["-f", &socket]);
    let mut full = vec!["--listen", socket.as_str()];
    full.extend_from_slice(nvim_arguments);
    log_call(&mut log, "nvim", &full);
    log
}

#[test]
fn attached_with_arguments_remote_opens_then_raises_the_window() {
    let case = fixture("v-attached", true);
    let output = run(&case, &["file", "-h"], "0");
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), ATTACHED);
    assert_eq!(stderr(&output), "");
    assert_eq!(case.argv_log(), attached_log(&case, Some(&["file", "-h"])));
    assert_eq!(
        case.env_log(),
        "nvr NVIM_APPNAME=[] set=set\n",
        "the exported NVIM_APPNAME is empty but set"
    );
}

#[test]
fn attached_without_arguments_only_focuses_the_window() {
    let case = fixture("v-attached-empty", true);
    let output = run(&case, &[], "0");
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), ATTACHED);
    assert_eq!(stderr(&output), "");
    assert_eq!(case.argv_log(), attached_log(&case, None));
    assert_eq!(case.env_log(), "");
}

#[test]
fn attached_keeps_going_when_helpers_fail() {
    let case = fixture("v-attached-fail", true);
    let output = case
        .command()
        .args(["file"])
        .env("LOCAL_BIN_MISC_V_SOCKET", case.socket_path())
        .env("FAKE_NC_CODE", "0")
        .env("FAKE_NVR_OUT", "nvr-out\n")
        .env("FAKE_NVR_ERR", "nvr-err\n")
        .env("FAKE_NVR_CODE", "3")
        .env("FAKE_HYPRCTL_OUT", "hypr-out\n")
        .env("FAKE_HYPRCTL_ERR", "hypr-err\n")
        .env("FAKE_HYPRCTL_CODE", "4")
        .output()
        .expect("run v");
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "nvr-out\n\u{2197}  nvim (attached)\n");
    assert_eq!(stderr(&output), "nvr-err\nhypr-err\n");
    assert_eq!(case.argv_log(), attached_log(&case, Some(&["file"])));
}

#[test]
fn attached_without_nvr_reports_it_and_still_focuses() {
    let case = fixture("v-no-nvr", true);
    case.remove_fake("nvr");
    let output = run(&case, &["file"], "0");
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), ATTACHED);
    assert_eq!(
        stderr(&output),
        format!("{BIN}: line 13: nvr: command not found\n")
    );
    let mut expected = String::new();
    log_call(&mut expected, "nc", &["-zU", &socket(&case)]);
    log_call(
        &mut expected,
        "hyprctl",
        &["dispatch", "focuswindow", "class:nwim"],
    );
    assert_eq!(case.argv_log(), expected);
}

#[test]
fn attached_without_hyprctl_reports_it_and_still_prints_the_status_line() {
    let case = fixture("v-no-hyprctl", true);
    case.remove_fake("hyprctl");
    let output = run(&case, &[], "0");
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), ATTACHED);
    assert_eq!(
        stderr(&output),
        format!("{BIN}: line 17: hyprctl: command not found\n")
    );
}

#[test]
fn nc_output_is_discarded_and_its_failure_starts_a_new_server() {
    let case = fixture("v-nc-fail", true);
    let output = case
        .command()
        .args(["file"])
        .env("LOCAL_BIN_MISC_V_SOCKET", case.socket_path())
        .env("FAKE_NC_CODE", "1")
        .env("FAKE_NC_OUT", "nc-out\n")
        .env("FAKE_NC_ERR", "nc-err\n")
        .env("FAKE_NVIM_OUT", "nvim-out\n")
        .env("FAKE_NVIM_ERR", "nvim-err\n")
        .env("FAKE_NVIM_CODE", "9")
        .output()
        .expect("run v");
    assert_eq!(exited(&output), 9);
    assert_eq!(stdout(&output), "nvim-out\n");
    assert_eq!(stderr(&output), "nvim-err\n");
    let mut expected = String::new();
    log_call(&mut expected, "nc", &["-zU", &socket(&case)]);
    expected.push_str(&fresh_log(&case, &["file"]));
    assert_eq!(case.argv_log(), expected);
    assert_eq!(case.env_log(), "nvim NVIM_APPNAME=[] set=set\n");
}

#[test]
fn an_absent_socket_skips_nc_entirely() {
    let case = fixture("v-fresh", false);
    let output = run(&case, &["-h", "x"], "0");
    assert_eq!(exited(&output), 0);
    assert_eq!(case.argv_log(), fresh_log(&case, &["-h", "x"]));
}

#[test]
fn a_regular_file_at_the_socket_path_is_not_a_server() {
    let case = fixture("v-regular", false);
    case.write(&case.socket_path(), "not a socket\n");
    let output = run(&case, &[], "0");
    assert_eq!(exited(&output), 0);
    assert_eq!(case.argv_log(), fresh_log(&case, &[]));
}

#[test]
fn a_missing_nc_falls_back_to_a_new_server_silently() {
    let case = fixture("v-no-nc", true);
    case.remove_fake("nc");
    let output = run(&case, &[], "0");
    assert_eq!(exited(&output), 0);
    assert_eq!(stderr(&output), "");
    assert_eq!(case.argv_log(), fresh_log(&case, &[]));
}

#[test]
fn a_missing_nvim_is_an_exec_failure_with_status_127() {
    let case = fixture("v-no-nvim", false);
    case.remove_fake("nvim");
    let output = run(&case, &[], "1");
    assert_eq!(exited(&output), 127);
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        format!("{BIN}: line 23: exec: nvim: not found\n")
    );
    assert_eq!(case.argv_log(), format!("rm\n  -f\n  {}\n", socket(&case)));
}

#[test]
fn a_missing_rm_is_reported_then_the_editor_still_starts() {
    let case = fixture("v-no-rm", false);
    case.remove_fake("rm");
    let output = run(&case, &[], "1");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stderr(&output),
        format!("{BIN}: line 21: rm: command not found\n")
    );
    let mut expected = String::new();
    log_call(&mut expected, "nvim", &["--listen", &socket(&case)]);
    assert_eq!(case.argv_log(), expected);
}

#[test]
fn the_helper_is_never_told_to_remove_a_real_socket_in_these_tests() {
    // The fixture's `rm` only logs; this asserts the tests themselves stay in
    // the temporary tree and the production default remains untouched.
    let case = fixture("v-tree", true);
    assert!(case.socket_path().starts_with(&case.root));
    let output = run(&case, &[], "0");
    assert_eq!(exited(&output), 0);
    assert!(stdout(&output).contains("attached"));
}
