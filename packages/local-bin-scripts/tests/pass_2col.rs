//! Hermetic tests for the `pass-2col` port: fake `vicinae`, `pass`, `wl-copy`
//! and `notify-send` programs record their argv and stdin, and the password
//! store is a temporary directory tree.

mod support;

use support::{exited, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_pass-2col");

const VICINAE: &str = r#"#!/bin/sh
printf 'vicinae\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
while IFS= read -r line; do printf '%s\n' "$line" >> "$FAKE_DMENU_IN"; done
printf '%s' "${FAKE_SEL:-}"
exit "${FAKE_SEL_CODE:-0}"
"#;

const PASS: &str = r#"#!/bin/sh
printf 'pass\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
case "$1" in
  otp)
    if [ "$2" = "code" ]; then
      printf '%s' "${FAKE_OTP:-}"
      exit "${FAKE_OTP_CODE:-0}"
    fi
    exit "${FAKE_OTP_C_CODE:-0}"
    ;;
  show)
    printf '%s' "${FAKE_SHOW:-}"
    exit "${FAKE_SHOW_CODE:-0}"
    ;;
  -c)
    exit "${FAKE_PASS_C_CODE:-0}"
    ;;
esac
exit 0
"#;

const WL_COPY: &str = r#"#!/bin/sh
printf 'wl-copy\n' >> "$FAKE_ARGV_LOG"
IFS= read -r value || true
printf '%s' "$value" >> "$FAKE_CLIP"
exit "${FAKE_WLCOPY_CODE:-0}"
"#;

const NOTIFY_SEND: &str = r#"#!/bin/sh
printf 'notify-send\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
exit "${FAKE_NOTIFY_CODE:-0}"
"#;

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("vicinae", VICINAE);
    case.write_fake("pass", PASS);
    case.write_fake("wl-copy", WL_COPY);
    case.write_fake("notify-send", NOTIFY_SEND);
    case
}

fn store(case: &Case) -> std::path::PathBuf {
    case.path("store")
}

fn populate_store(case: &Case) {
    let root = store(case);
    for entry in [
        "alpha.gpg",
        "dir/beta.gpg",
        ".gpg-id",
        ".git/secret.gpg",
        "nested/.git/inner.gpg",
        "space name.gpg",
    ] {
        case.write(&root.join(entry), "fixture");
    }
}

fn expected_prefix() -> &'static str {
    "vicinae\n  dmenu\n  -p\n  pass ❯>\n"
}

#[test]
fn otp_code_is_preferred_and_copied() {
    let case = fixture("otp");
    populate_store(&case);
    let output = case
        .command()
        .env("PASSWORD_STORE_DIR", store(&case))
        .env("FAKE_SEL", "alpha")
        .env("FAKE_OTP", "123456\nignored second line\n")
        .env("FAKE_SHOW", "hunter2\n")
        .output()
        .expect("run pass-2col");
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");
    assert_eq!(
        std::fs::read_to_string(case.path("clip.log")).unwrap(),
        "123456"
    );
    assert_eq!(
        case.argv_log(),
        format!(
            "{}pass\n  otp\n  code\n  --\n  alpha\nwl-copy\nnotify-send\n  pass\n  OTP copied: alpha\n",
            expected_prefix()
        )
    );
    assert!(!case.argv_log().contains("pass\n  show"), "OTP must win");
}

#[test]
fn password_first_line_is_used_without_an_otp() {
    let case = fixture("password");
    populate_store(&case);
    let output = case
        .command()
        .env("PASSWORD_STORE_DIR", store(&case))
        .env("FAKE_SEL", "dir/beta")
        .env("FAKE_OTP_CODE", "1")
        .env("FAKE_SHOW", "hunter2\nsecond line\n")
        .output()
        .expect("run pass-2col");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        std::fs::read_to_string(case.path("clip.log")).unwrap(),
        "hunter2"
    );
    assert!(case.argv_log().ends_with(
        "pass\n  show\n  --\n  dir/beta\nwl-copy\nnotify-send\n  pass\n  Copied: dir/beta\n"
    ));
}

#[test]
fn raw_otpauth_secret_uses_pass_otp_and_warns() {
    let case = fixture("otpauth");
    populate_store(&case);
    let output = case
        .command()
        .env("PASSWORD_STORE_DIR", store(&case))
        .env("FAKE_SEL", "alpha")
        .env("FAKE_OTP", "")
        .env("FAKE_SHOW", "otpauth://totp/x?secret=y\n")
        .env("FAKE_OTP_C_CODE", "1")
        .output()
        .expect("run pass-2col");
    assert_eq!(exited(&output), 0);
    assert!(
        !case.path("clip.log").exists(),
        "otpauth URI must not be copied"
    );
    let log = case.argv_log();
    assert!(
        log.contains("pass\n  otp\n  -c\n  --\n  alpha\n"),
        "argv: {log}"
    );
    assert!(
        log.ends_with("notify-send\n  pass\n  OTP entry needs pass-otp: alpha\n"),
        "argv: {log}"
    );
    assert!(!log.contains("wl-copy\n"), "argv: {log}");
}

#[test]
fn empty_or_cancelled_selection_exits_quietly() {
    let case = fixture("cancelled");
    populate_store(&case);
    let output = case
        .command()
        .env("PASSWORD_STORE_DIR", store(&case))
        .env("FAKE_SEL", "")
        .output()
        .expect("run pass-2col");
    assert_eq!(exited(&output), 0);
    assert_eq!(case.argv_log(), expected_prefix());
}

#[test]
fn missing_or_empty_store_exits_quietly() {
    let case = fixture("no-store");
    let output = case.run(&[]);
    assert_eq!(exited(&output), 0);
    assert_eq!(case.argv_log(), "");

    std::fs::create_dir_all(store(&case)).expect("create store");
    case.write(&store(&case).join(".gpg-id"), "id");
    let output = case
        .command()
        .env("PASSWORD_STORE_DIR", store(&case))
        .output()
        .expect("run pass-2col");
    assert_eq!(exited(&output), 0);
    assert_eq!(case.argv_log(), "");
}

#[test]
fn entries_are_filtered_sorted_and_stripped() {
    let case = fixture("entries");
    populate_store(&case);
    let output = case
        .command()
        .env("PASSWORD_STORE_DIR", store(&case))
        .env("FAKE_SEL", "space name")
        .env("FAKE_OTP_CODE", "1")
        .env("FAKE_SHOW", "pw\n")
        .output()
        .expect("run pass-2col");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.read("dmenu-in.log"),
        "alpha\ndir/beta\nnested/.git/inner\nspace name\n"
    );
    assert!(case
        .argv_log()
        .contains("pass\n  show\n  --\n  space name\n"));
}

#[test]
fn selection_trailing_newlines_are_stripped() {
    let case = fixture("selection-newlines");
    populate_store(&case);
    let output = case
        .command()
        .env("PASSWORD_STORE_DIR", store(&case))
        .env("FAKE_SEL", "alpha\n\n\n")
        .env("FAKE_OTP", "code")
        .output()
        .expect("run pass-2col");
    assert_eq!(exited(&output), 0);
    assert!(case
        .argv_log()
        .contains("pass\n  otp\n  code\n  --\n  alpha\n"));
    assert_eq!(
        std::fs::read_to_string(case.path("clip.log")).unwrap(),
        "code"
    );
}

#[test]
fn home_store_is_the_fallback() {
    let case = fixture("home-store");
    let home_store = case.home.join(".local/share/pass");
    case.write(&home_store.join("home-entry.gpg"), "fixture");
    let output = case
        .command()
        .env("FAKE_SEL", "home-entry")
        .env("FAKE_OTP_CODE", "1")
        .env("FAKE_SHOW", "pw\n")
        .output()
        .expect("run pass-2col");
    assert_eq!(exited(&output), 0);
    assert_eq!(case.read("dmenu-in.log"), "home-entry\n");
}

#[test]
fn password_store_dir_beats_home() {
    let case = fixture("precedence");
    populate_store(&case);
    let home_store = case.home.join(".local/share/pass");
    case.write(&home_store.join("home-entry.gpg"), "fixture");
    let output = case
        .command()
        .env("PASSWORD_STORE_DIR", store(&case))
        .env("FAKE_SEL", "alpha")
        .env("FAKE_OTP", "code")
        .output()
        .expect("run pass-2col");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.read("dmenu-in.log"),
        "alpha\ndir/beta\nnested/.git/inner\nspace name\n"
    );
}

#[test]
fn missing_home_and_store_dir_is_an_unbound_variable() {
    let case = fixture("no-home");
    let output = case
        .command()
        .env_remove("HOME")
        .output()
        .expect("run pass-2col");
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        format!(
            "{}: line 7: HOME: unbound variable\n",
            case.program().display()
        )
    );
}

#[test]
fn missing_wl_copy_falls_back_to_pass_otp() {
    let case = fixture("no-wl-copy");
    populate_store(&case);
    case.remove_fake("wl-copy");
    let output = case
        .command()
        .env("PASSWORD_STORE_DIR", store(&case))
        .env("FAKE_SEL", "alpha")
        .env("FAKE_OTP", "654321\n")
        .output()
        .expect("run pass-2col");
    assert_eq!(exited(&output), 0);
    let log = case.argv_log();
    assert!(
        log.contains("pass\n  otp\n  -c\n  --\n  alpha\n"),
        "argv: {log}"
    );
    assert!(log.ends_with("notify-send\n  pass\n  OTP copied: alpha\n"));
}

#[test]
fn missing_notify_send_does_not_matter() {
    let case = fixture("no-notify");
    populate_store(&case);
    case.remove_fake("notify-send");
    let output = case
        .command()
        .env("PASSWORD_STORE_DIR", store(&case))
        .env("FAKE_SEL", "alpha")
        .env("FAKE_OTP", "112233\n")
        .output()
        .expect("run pass-2col");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        std::fs::read_to_string(case.path("clip.log")).unwrap(),
        "112233"
    );
    assert!(!case.argv_log().contains("notify-send\n"));
}

#[test]
fn empty_password_copies_nothing() {
    let case = fixture("empty-password");
    populate_store(&case);
    let output = case
        .command()
        .env("PASSWORD_STORE_DIR", store(&case))
        .env("FAKE_SEL", "alpha")
        .env("FAKE_OTP_CODE", "1")
        .env("FAKE_SHOW", "")
        .output()
        .expect("run pass-2col");
    assert_eq!(exited(&output), 0);
    assert!(!case.path("clip.log").exists());
    assert!(!case.argv_log().contains("wl-copy"));
    assert!(!case.argv_log().contains("notify-send"));
}

#[test]
fn failed_pass_show_keeps_its_stdout() {
    let case = fixture("show-failure");
    populate_store(&case);
    let output = case
        .command()
        .env("PASSWORD_STORE_DIR", store(&case))
        .env("FAKE_SEL", "alpha")
        .env("FAKE_OTP_CODE", "1")
        .env("FAKE_SHOW", "secret\n")
        .env("FAKE_SHOW_CODE", "2")
        .output()
        .expect("run pass-2col");
    // The shell keeps the pipeline's stdout even when `pass show` fails
    // (`|| true` only affects the status), so the first line is still copied.
    assert_eq!(exited(&output), 0);
    assert_eq!(
        std::fs::read_to_string(case.path("clip.log")).unwrap(),
        "secret"
    );
}

#[test]
fn wl_copy_failure_is_propagated() {
    let case = fixture("wl-copy-failure");
    populate_store(&case);
    let output = case
        .command()
        .env("PASSWORD_STORE_DIR", store(&case))
        .env("FAKE_SEL", "alpha")
        .env("FAKE_OTP", "123456\n")
        .env("FAKE_WLCOPY_CODE", "5")
        .output()
        .expect("run pass-2col");
    // `printf ... | wl-copy` under `set -e` + `pipefail` makes the clipboard
    // status the script's status.
    assert_eq!(exited(&output), 5);
}

#[test]
fn vicinae_failure_is_propagated() {
    let case = fixture("vicinae-failure");
    populate_store(&case);
    let output = case
        .command()
        .env("PASSWORD_STORE_DIR", store(&case))
        .env("FAKE_SEL_CODE", "3")
        .output()
        .expect("run pass-2col");
    assert_eq!(exited(&output), 3);
}
