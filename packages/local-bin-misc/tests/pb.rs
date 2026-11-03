//! Hermetic tests for the `pb` port: a fake `curl` logs argv and stdin; the
//! payloads live in the per-case temporary tree.

mod support;

use std::os::unix::fs::PermissionsExt;

use support::{exited, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_pb");
const USAGE: &str = include_str!("fixtures/pb-usage.txt");
const DEFAULT_UA: &str = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/44.0.2403.157 Safari/537.36";

const CURL: &str = r#"#!/bin/sh
printf 'curl\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
printf 'stdin\n' >> "$FAKE_ARGV_LOG"
while IFS= read -r line || [ -n "$line" ]; do printf '  %s\n' "$line" >> "$FAKE_ARGV_LOG"; done 2>/dev/null
printf '%s' "${FAKE_CURL_OUT:-}"
printf '%s' "${FAKE_CURL_ERR:-}" >&2
exit "${FAKE_CURL_CODE:-0}"
"#;

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("curl", CURL);
    case
}

fn payload(case: &Case, content: &str) -> String {
    let path = case.path("payload.txt");
    case.write(&path, content);
    path.to_string_lossy().into_owned()
}

fn expected_call(arguments: &[&str], stdin: &str) -> String {
    let mut log = String::from("curl\n");
    for argument in arguments {
        log.push_str(&format!("  {argument}\n"));
    }
    log.push_str("stdin\n");
    for line in stdin.lines() {
        log.push_str(&format!("  {line}\n"));
    }
    log
}

fn base_argv(service_args: &[&str]) -> Vec<String> {
    let mut argv = vec!["-fsS".to_string(), "-A".to_string(), DEFAULT_UA.to_string()];
    argv.extend(service_args.iter().map(|value| value.to_string()));
    argv
}

#[test]
fn help_variants_print_usage_without_touching_tools() {
    for argument in ["-h", "--help", "help", "?"] {
        let case = Case::new("pb-help", BIN);
        let output = case.run(&[argument]);
        assert_eq!(exited(&output), 0, "argument {argument}");
        assert_eq!(stdout(&output), USAGE, "argument {argument}");
        assert_eq!(stderr(&output), "", "argument {argument}");
        assert_eq!(case.argv_log(), "", "argument {argument}");
        assert_eq!(case.env_log(), "", "argument {argument}");
    }
}

#[test]
fn unknown_service_prints_usage_after_the_missing_curl_warning() {
    let case = Case::new("pb-unknown", BIN);
    let output = case.run(&["bogus"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), USAGE);
    assert_eq!(stderr(&output), "pb: missing curl\n");
    assert_eq!(case.argv_log(), "");
}

#[test]
fn temp_uploads_the_file_and_propagates_curl_output_and_status() {
    let case = fixture("pb-temp");
    let file = payload(&case, "hello\nworld\n");
    let output = case
        .command()
        .args(["temp", &file])
        .env("FAKE_CURL_OUT", "service-out\n")
        .env("FAKE_CURL_ERR", "service-err\n")
        .env("FAKE_CURL_CODE", "5")
        .output()
        .expect("run pb");
    assert_eq!(exited(&output), 5);
    assert_eq!(stdout(&output), "service-out\n");
    assert_eq!(stderr(&output), "service-err\n");
    let argv = base_argv(&["-F", "file=@-", "https://temp.sh/upload"]);
    assert_eq!(
        case.argv_log(),
        expected_call(
            &argv.iter().map(String::as_str).collect::<Vec<_>>(),
            "hello\nworld\n"
        )
    );
}

#[test]
fn each_service_arm_has_its_exact_curl_argv() {
    let arms: &[(&[&str], &[&str])] = &[
        (
            &["temp", "tmp", "temp.sh"],
            &["-F", "file=@-", "https://temp.sh/upload"],
        ),
        (
            &["iotek", "iopaste", "p.iotek.org", "iop-anything"],
            &["-T", "-", "https://p.iotek.org"],
        ),
        (
            &["uguu", "uguu.se", "upload"],
            &["-F", "files[]=@-", "https://uguu.se/upload?output=text"],
        ),
        (
            &["catbox", "catbox.moe", "cat-anything"],
            &[
                "-F",
                "reqtype=fileupload",
                "-F",
                "fileToUpload=@-",
                "https://catbox.moe/user/api.php",
            ],
        ),
    ];
    for (services, service_args) in arms {
        for service in *services {
            let case = fixture("pb-arms");
            let file = payload(&case, "");
            let output = case.run(&[service, &file]);
            assert_eq!(exited(&output), 0, "service {service}");
            assert_eq!(stderr(&output), "", "service {service}");
            let argv = base_argv(service_args);
            assert_eq!(
                case.argv_log(),
                expected_call(&argv.iter().map(String::as_str).collect::<Vec<_>>(), ""),
                "service {service}"
            );
        }
    }
}

#[test]
fn default_stdin_and_an_empty_second_argument_stream_stdin() {
    let case = fixture("pb-stdin");
    let output = case.run_with_stdin(&["temp"], b"stream-a\nstream-b\n");
    assert_eq!(exited(&output), 0);
    let argv = base_argv(&["-F", "file=@-", "https://temp.sh/upload"]);
    assert_eq!(
        case.argv_log(),
        expected_call(
            &argv.iter().map(String::as_str).collect::<Vec<_>>(),
            "stream-a\nstream-b\n"
        )
    );

    std::fs::write(case.path("argv.log"), "").expect("clear argv log");
    let output = case.run_with_stdin(&["temp", ""], b"empty-arg\n");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv_log(),
        expected_call(
            &argv.iter().map(String::as_str).collect::<Vec<_>>(),
            "empty-arg\n"
        )
    );
}

#[test]
fn custom_user_agent_replaces_the_default_and_empty_means_default() {
    let case = fixture("pb-ua");
    let file = payload(&case, "");
    let output = case
        .command()
        .args(["temp", &file])
        .env("UA", "custom-agent/1.0")
        .output()
        .expect("run pb");
    assert_eq!(exited(&output), 0);
    let argv = vec![
        "-fsS",
        "-A",
        "custom-agent/1.0",
        "-F",
        "file=@-",
        "https://temp.sh/upload",
    ];
    assert_eq!(case.argv_log(), expected_call(&argv, ""));

    std::fs::write(case.path("argv.log"), "").expect("clear argv log");
    let output = case
        .command()
        .args(["temp", &file])
        .env("UA", "")
        .output()
        .expect("run pb");
    assert_eq!(exited(&output), 0);
    let argv = base_argv(&["-F", "file=@-", "https://temp.sh/upload"]);
    assert_eq!(
        case.argv_log(),
        expected_call(&argv.iter().map(String::as_str).collect::<Vec<_>>(), "")
    );
}

#[test]
fn a_missing_file_reports_twice_and_never_runs_curl() {
    let case = fixture("pb-missing");
    let missing = case.path("nope.bin");
    let missing = missing.to_string_lossy().into_owned();
    let output = case.run(&["temp", &missing]);
    assert_eq!(exited(&output), 1);
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        format!(
            "pb: no such file: {missing}\n{BIN}: line 63: {missing}: No such file or directory\n"
        )
    );
    assert_eq!(case.argv_log(), "");
}

#[test]
fn a_dash_argument_is_opened_as_a_file_named_dash() {
    let case = fixture("pb-dash");
    let output = case.run(&["temp", "-"]);
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        format!("{BIN}: line 63: -: No such file or directory\n")
    );
    assert_eq!(case.argv_log(), "");

    // With a file literally named "-" the original streams that file.
    case.write(&case.path("-"), "dash-data\n");
    let output = case.run(&["temp", "-"]);
    assert_eq!(exited(&output), 0);
    let argv = base_argv(&["-F", "file=@-", "https://temp.sh/upload"]);
    assert_eq!(
        case.argv_log(),
        expected_call(
            &argv.iter().map(String::as_str).collect::<Vec<_>>(),
            "dash-data\n"
        )
    );
}

#[test]
fn a_directory_is_warned_about_but_curl_still_runs() {
    let case = fixture("pb-dir");
    let directory = case.path("upload-dir");
    std::fs::create_dir_all(&directory).expect("create directory");
    let output = case.run(&["temp", directory.to_str().expect("utf-8 path")]);
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stderr(&output),
        format!("pb: no such file: {}\n", directory.display())
    );
    let argv = base_argv(&["-F", "file=@-", "https://temp.sh/upload"]);
    assert_eq!(
        case.argv_log(),
        expected_call(&argv.iter().map(String::as_str).collect::<Vec<_>>(), "")
    );
}

#[test]
fn curl_status_is_the_script_status_and_extra_arguments_are_ignored() {
    let case = fixture("pb-status");
    let file = payload(&case, "");
    let output = case
        .command()
        .args(["temp", &file, "ignored"])
        .env("FAKE_CURL_CODE", "7")
        .output()
        .expect("run pb");
    assert_eq!(exited(&output), 7);
    let argv = base_argv(&["-F", "file=@-", "https://temp.sh/upload"]);
    assert_eq!(
        case.argv_log(),
        expected_call(&argv.iter().map(String::as_str).collect::<Vec<_>>(), "")
    );
}

#[test]
fn a_missing_curl_warns_then_reports_command_not_found() {
    let case = Case::new("pb-no-curl", BIN);
    let file = payload(&case, "");
    let output = case.run(&["temp", &file]);
    assert_eq!(exited(&output), 127);
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        format!("pb: missing curl\n{BIN}: line 63: curl: command not found\n")
    );
    assert_eq!(case.argv_log(), "");
}

#[test]
fn unreadable_and_dangling_paths_fail_like_shell_redirection() {
    let case = fixture("pb-unreadable");
    let file = payload(&case, "secret");
    let mut permissions = std::fs::metadata(&file)
        .expect("stat payload")
        .permissions();
    permissions.set_mode(0o000);
    std::fs::set_permissions(&file, permissions).expect("chmod payload");
    let output = case.run(&["temp", &file]);
    if exited(&output) == 0 {
        // Running as root defeats the permission fixture; nothing to assert.
        return;
    }
    assert_eq!(exited(&output), 1);
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        format!("{BIN}: line 63: {file}: Permission denied\n")
    );
    assert_eq!(case.argv_log(), "");

    let dangling = case.path("dangling");
    std::os::unix::fs::symlink(case.path("nowhere"), &dangling).expect("create symlink");
    let dangling = dangling.to_string_lossy().into_owned();
    let output = case.run(&["temp", &dangling]);
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        format!(
            "pb: no such file: {dangling}\n{BIN}: line 63: {dangling}: No such file or directory\n"
        )
    );
}
