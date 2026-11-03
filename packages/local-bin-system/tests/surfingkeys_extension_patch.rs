//! Hermetic tests for the `surfingkeys-extension-patch` port: version-directory
//! selection, the five guarded patch steps, the `.orig` backup, the idempotent
//! second run, the upgrade from the first registration helper, and the
//! fail-loudly contract. `logger` is a fake that records argv and can fail.

mod support;

use std::path::PathBuf;

use support::{exited, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_surfingkeys-extension-patch");

const EXTENSION: &str = "gfbliohnnapiefjpjlpjnehglfpaknnc";

const LOGGER: &str = r#"#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_ARGV_LOG"
exit "${FAKE_LOGGER_CODE:-0}"
"#;

const BACKGROUND: &str = "(()=>{\"use strict\";var a=e.localPath?B(e.localPath,function(t){e.snippets=t,o(e)},z);}))();\n";

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("logger", LOGGER);
    case
}

fn base(case: &Case) -> PathBuf {
    case.home
        .join(".config/vivaldi/Default/Extensions")
        .join(EXTENSION)
}

fn version_dir(case: &Case, version: &str) -> PathBuf {
    let directory = base(case).join(version);
    std::fs::create_dir_all(directory.join("pages")).expect("create version dir");
    directory
}

fn install(case: &Case, version: &str, background: &str) -> PathBuf {
    let directory = version_dir(case, version);
    case.write(&directory.join("background.js"), background);
    directory
}

fn logger_lines(case: &Case) -> Vec<String> {
    case.argv_log().lines().map(str::to_string).collect()
}

fn logged(case: &Case) -> String {
    case.argv_log()
}

#[test]
fn patches_the_newest_version_directory() {
    let case = fixture("patch");
    install(&case, "1.18.0", "old-background\n");
    let newest = install(&case, "1.19.3", BACKGROUND);
    let css = newest.join("pages/markdown.css");
    case.write(&css, "table { background-color: #f8f8f8; }\n");

    let output = case.run(&[]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stderr(&output), "");

    let background = case.read_at(&newest.join("background.js"));
    assert!(
        background
            .starts_with("const NEG_SK_REGISTER2=function(s){var c=\"import(\\\"./api.js\\\")"),
        "{background}"
    );
    assert!(background.contains("const NEG_SK_URL=\"http://localhost:18888/surfingkeys.js\";\n"));
    assert!(background.contains(
        "chrome.storage.sync.set({localPath:NEG_SK_URL});\nchrome.storage.local.set({localPath:NEG_SK_URL});\n(()=>{\"use strict\";"
    ));
    assert!(background.contains(
        "var a=(e.localPath=\"http://localhost:18888/surfingkeys.js\",e.localPath)?B(e.localPath,function(t){e.snippets=t,NEG_SK_REGISTER2(t),o(e)},z);"
    ));
    assert!(!background.contains("NEG_SK_REGISTER(t)"));
    assert_eq!(
        case.read_at(&css),
        "table { background-color: transparent; }\n"
    );

    // The older version directory is untouched.
    assert_eq!(
        case.read_at(&base(&case).join("1.18.0/background.js")),
        "old-background\n"
    );

    let lines = logger_lines(&case);
    assert_eq!(lines.len(), 5, "{lines:?}");
    assert!(lines[0].contains("(URL injection)"), "{lines:?}");
    assert!(
        lines[1].contains("(config re-registration helper)"),
        "{lines:?}"
    );
    assert!(lines[2].contains("(hardcoded config URL)"), "{lines:?}");
    assert!(
        lines[3].contains("(refresh registration after fetch)"),
        "{lines:?}"
    );
    assert!(lines[4].contains("(no zebra)"), "{lines:?}");
    // The original's double slash in the version path is preserved.
    assert!(lines[0].contains("1.19.3//background.js"), "{lines:?}");
}

#[test]
fn the_orig_backup_keeps_the_unpatched_file() {
    let case = fixture("orig");
    let directory = install(&case, "1.19.3", BACKGROUND);
    let output = case.run(&[]);
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.read_at(&directory.join("background.js.orig")),
        BACKGROUND
    );
}

#[test]
fn a_second_run_is_a_no_op() {
    let case = fixture("idempotent");
    let directory = install(&case, "1.19.3", BACKGROUND);
    assert_eq!(exited(&case.run(&[])), 0);
    let after_first = case.read_at(&directory.join("background.js"));
    let log_after_first = logged(&case);
    assert_eq!(exited(&case.run(&[])), 0);
    assert_eq!(case.read_at(&directory.join("background.js")), after_first);
    // Only the first run logged; the guarded steps skip on the second.
    assert_eq!(logged(&case), log_after_first);
}

#[test]
fn only_the_newest_version_by_version_sort_is_patched() {
    let case = fixture("version-sort");
    install(&case, "1.9.2", "keep-1.9.2\n");
    install(&case, "1.10.0", "keep-1.10.0\n");
    let newest = install(&case, "1.19.3", BACKGROUND);
    assert_eq!(exited(&case.run(&[])), 0);
    assert!(case
        .read_at(&newest.join("background.js"))
        .contains("NEG_SK_URL"));
    assert_eq!(
        case.read_at(&base(&case).join("1.9.2/background.js")),
        "keep-1.9.2\n"
    );
    assert_eq!(
        case.read_at(&base(&case).join("1.10.0/background.js")),
        "keep-1.10.0\n"
    );

    // 1.19.10 sorts above 1.19.3 for both sort -V and the port.
    let tenth = install(&case, "1.19.10", BACKGROUND);
    assert_eq!(exited(&case.run(&[])), 0);
    assert!(case
        .read_at(&tenth.join("background.js"))
        .contains("NEG_SK_URL"));
}

#[test]
fn no_version_directory_exits_without_a_message() {
    let case = fixture("no-version");
    std::fs::create_dir_all(base(&case)).expect("create extension base");
    let output = case.run(&[]);
    // `set -e` + `pipefail` make the failing `ls` abort with status 2 before
    // the script's own `-z` check; the port keeps the observable status.
    assert_eq!(exited(&output), 2);
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");
}

#[test]
fn a_missing_extension_base_also_exits_2() {
    let case = fixture("no-base");
    let output = case.run(&[]);
    assert_eq!(exited(&output), 2);
    assert_eq!(stderr(&output), "");
}

#[test]
fn missing_anchors_fail_loudly_but_still_apply_the_safe_steps() {
    let case = fixture("missing-anchors");
    let directory = install(&case, "1.19.3", "unrelated-content\n");
    let output = case.run(&[]);
    assert_eq!(exited(&output), 1);
    assert_eq!(stdout(&output), "");
    let lines = logger_lines(&case);
    assert_eq!(lines.len(), 7, "{lines:?}");
    assert!(
        lines[0].starts_with("-p user.err surfingkeys-patch: URL-injection anchor not found"),
        "{lines:?}"
    );
    assert!(
        lines[1].contains("(config re-registration helper)"),
        "{lines:?}"
    );
    assert!(
        lines[2].starts_with("-p user.err surfingkeys-patch: config-URL read anchor not found"),
        "{lines:?}"
    );
    assert!(
        lines[3].starts_with("-p user.err surfingkeys-patch: fetch-callback anchor not found"),
        "{lines:?}"
    );
    assert!(
        lines[4].contains("critical patch missing: URL injection"),
        "{lines:?}"
    );
    assert!(
        lines[5].contains("critical patch missing: registration refresh"),
        "{lines:?}"
    );
    assert!(
        lines[6].contains("critical patch missing: hardcoded config URL"),
        "{lines:?}"
    );

    // Step 2 still prepended the helper; nothing else invented.
    let background = case.read_at(&directory.join("background.js"));
    assert!(background.starts_with("const NEG_SK_REGISTER2="));
    assert!(background.ends_with("unrelated-content\n"));
}

#[test]
fn the_first_registration_helper_is_upgraded() {
    let case = fixture("upgrade");
    let old_helper = "const NEG_SK_REGISTER=function(s){var c=\"import(\\\"./api.js\\\")\"};\n";
    let background = format!(
        "{old_helper}(()=>{{\"use strict\";var x=NEG_SK_REGISTER(t);var y=e.localPath?B(e.localPath,other);}})();\n"
    );
    let directory = install(&case, "1.19.3", &background);
    let output = case.run(&[]);
    assert_eq!(exited(&output), 0);
    let patched = case.read_at(&directory.join("background.js"));
    assert!(
        !patched.contains("const NEG_SK_REGISTER=function"),
        "{patched}"
    );
    assert!(patched.starts_with("const NEG_SK_REGISTER2="), "{patched}");
    assert!(patched.contains("NEG_SK_REGISTER2(t)"), "{patched}");
    assert!(!patched.contains("NEG_SK_REGISTER(t)"), "{patched}");
    assert!(logged(&case).contains("(refresh registration after fetch, upgraded)"));
}

#[test]
fn a_file_without_a_trailing_newline_keeps_it_that_way() {
    let case = fixture("no-newline");
    let background = "(()=>{\"use strict\";var a=e.localPath?B(e.localPath,function(t){e.snippets=t,o(e)},z);}))();";
    let directory = install(&case, "1.19.3", background);
    assert_eq!(exited(&case.run(&[])), 0);
    let patched = case.read_at(&directory.join("background.js"));
    assert!(!patched.ends_with('\n'), "{patched:?}");
}

#[test]
fn a_missing_markdown_file_is_not_an_error() {
    let case = fixture("no-css");
    install(&case, "1.19.3", BACKGROUND);
    let output = case.run(&[]);
    assert_eq!(exited(&output), 0);
    assert!(!logged(&case).contains("(no zebra)"));
}

#[test]
fn a_missing_logger_exits_127_like_a_shell() {
    let case = fixture("no-logger");
    case.remove_fake("logger");
    install(&case, "1.19.3", BACKGROUND);
    let output = case.run(&[]);
    assert_eq!(exited(&output), 127);
}

#[test]
fn a_failing_logger_aborts_with_its_status() {
    let case = fixture("logger-fails");
    install(&case, "1.19.3", BACKGROUND);
    let output = case.run_env(&[], &[("FAKE_LOGGER_CODE", "9")]);
    assert_eq!(exited(&output), 9);
}

#[test]
fn missing_background_js_fails_without_touching_the_tree() {
    let case = fixture("no-background");
    version_dir(&case, "1.19.3");
    let output = case.run(&[]);
    assert_eq!(exited(&output), 1);
    assert!(logged(&case).contains("URL-injection anchor not found"));
    assert!(!case
        .path("home/.config/vivaldi/Default/Extensions")
        .join(EXTENSION)
        .join("1.19.3/background.js")
        .exists());
}

#[test]
fn help_is_not_a_mode_and_is_treated_as_contentless() {
    let case = fixture("no-help");
    // The original has no argument handling at all: extra argv is ignored.
    install(&case, "1.19.3", BACKGROUND);
    let output = case.run(&["--help"]);
    assert_eq!(exited(&output), 0);
    assert!(case
        .read_at(&case.home.join(format!(
            ".config/vivaldi/Default/Extensions/{EXTENSION}/1.19.3/background.js"
        )))
        .contains("NEG_SK_URL"));
}
