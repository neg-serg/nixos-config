//! Hermetic tests for the `vsmlrt-models` port: the release URL, the
//! `VSMLRT_MODELS` destination, the `curl`/`7zz` argv (including 7zz's working
//! directory and the `-oDEST` spelling), the cleanup and the status paths.

mod support;

use support::{exited, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_vsmlrt-models");

const CURL: &str = r#"#!/bin/sh
printf 'cmd curl\n' >> "$FAKE_ARGV_LOG"
for argument in "$@"; do printf '  %s\n' "$argument" >> "$FAKE_ARGV_LOG"; done
destination=""
previous=""
for argument in "$@"; do
  if [ "$previous" = "-o" ]; then destination=$argument; fi
  previous=$argument
done
[ -n "$destination" ] && printf 'archive' > "$destination"
exit "${FAKE_CURL_CODE:-0}"
"#;

const SEVEN: &str = r#"#!/bin/sh
printf 'cmd 7zz\n' >> "$FAKE_ARGV_LOG"
for argument in "$@"; do printf '  %s\n' "$argument" >> "$FAKE_ARGV_LOG"; done
printf '  pwd %s\n' "$PWD" >> "$FAKE_ARGV_LOG"
exit "${FAKE_7ZZ_CODE:-0}"
"#;

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("curl", CURL);
    case.write_fake("7zz", SEVEN);
    case
}

fn tmp_entries(case: &Case) -> Vec<String> {
    std::fs::read_dir(&case.tmp)
        .map(|entries| {
            entries
                .flatten()
                .map(|entry| entry.file_name().to_string_lossy().into_owned())
                .collect()
        })
        .unwrap_or_default()
}

#[test]
fn default_version_downloads_and_extracts() {
    let case = fixture("default");
    // The literal /zero/ai default is never exercised: tests must not touch
    // the host asset tree. The version default and URL are still pinned.
    let destination = case.path("models");
    let output = case.run_env(&[], &[("VSMLRT_MODELS", &destination.to_string_lossy())]);
    assert_eq!(exited(&output), 0);
    let destination_text = destination.to_string_lossy();
    assert_eq!(
        stdout(&output),
        format!(
            concat!(
                "Downloading models v15.16 ...\n",
                "Models installed to {}\n",
                "Example VS script (interpolation):\n",
                "  import vapoursynth as vs\n",
                "  core = vs.core; core.std.LoadPlugin(path=\"{}/../../lib/libvsncnn.so\")\n",
            ),
            destination_text, destination_text
        )
    );
    assert_eq!(stderr(&output), "");
    let argv = case.argv_log();
    assert!(
        argv.contains("cmd curl\n  -L\n  --fail\n  -x\n  socks5h://127.0.0.1:10808\n  -o\n"),
        "{argv}"
    );
    assert!(
        argv.contains(
            "https://github.com/AmusementClub/vs-mlrt/releases/download/v15.16/models.v15.16.7z"
        ),
        "{argv}"
    );
    assert!(
        argv.contains(&format!(
            "cmd 7zz\n  x\n  -y\n  -o{}\n  models.7z\n",
            destination.to_string_lossy()
        )),
        "{argv}"
    );
    assert!(tmp_entries(&case).is_empty(), "{:?}", tmp_entries(&case));
}

#[test]
fn a_version_argument_changes_the_url_and_destination() {
    let case = fixture("version");
    let destination = case.path("models");
    let output = case.run_env(
        &["v16.0"],
        &[("VSMLRT_MODELS", &destination.to_string_lossy())],
    );
    assert_eq!(exited(&output), 0);
    assert!(stdout(&output).starts_with("Downloading models v16.0 ...\n"));
    assert!(case.argv_log().contains("models.v16.0.7z"));
}

#[test]
fn the_destination_can_be_overridden() {
    let case = fixture("dest");
    let destination = case.path("models");
    let output = case.run_env(&[], &[("VSMLRT_MODELS", &destination.to_string_lossy())]);
    assert_eq!(exited(&output), 0);
    assert!(destination.is_dir());
    assert!(case
        .argv_log()
        .contains(&format!("  -o{}\n", destination.to_string_lossy())));
    assert!(stdout(&output).contains(&format!(
        "Models installed to {}",
        destination.to_string_lossy()
    )));
}

#[test]
fn seven_zz_runs_inside_the_temporary_directory() {
    let case = fixture("cwd");
    let destination = case.path("models");
    let _ = case.run_env(&[], &[("VSMLRT_MODELS", &destination.to_string_lossy())]);
    let log = case.argv_log();
    let temp = log
        .lines()
        .find(|line| line.starts_with("  pwd "))
        .expect("pwd logged")
        .to_string();
    let path = temp.trim_start_matches("  pwd ");
    assert!(
        path.starts_with(&case.tmp.to_string_lossy().into_owned()),
        "{path}"
    );
    assert!(path.contains("tmp."), "{path}");
}

#[test]
fn curl_failure_propagates_and_skips_extraction() {
    let case = fixture("curl-fail");
    let destination = case.path("models");
    let output = case.run_env(
        &[],
        &[
            ("VSMLRT_MODELS", &destination.to_string_lossy()),
            ("FAKE_CURL_CODE", "6"),
        ],
    );
    assert_eq!(exited(&output), 6);
    assert!(!case.argv_log().contains("cmd 7zz"));
}

#[test]
fn seven_zz_failure_propagates() {
    let case = fixture("seven-fail");
    let destination = case.path("models");
    let output = case.run_env(
        &[],
        &[
            ("VSMLRT_MODELS", &destination.to_string_lossy()),
            ("FAKE_7ZZ_CODE", "8"),
        ],
    );
    assert_eq!(exited(&output), 8);
    // `set -e` aborts before the cleanup in the original as well.
    assert!(!tmp_entries(&case).is_empty());
}

#[test]
fn a_missing_seven_zz_exits_127() {
    let case = fixture("no-seven");
    case.remove_fake("7zz");
    let destination = case.path("models");
    let output = case.run_env(&[], &[("VSMLRT_MODELS", &destination.to_string_lossy())]);
    assert_eq!(exited(&output), 127);
    assert!(!tmp_entries(&case).is_empty());
}

#[test]
fn an_unwritable_destination_fails_before_extraction() {
    let case = fixture("dest-fail");
    let blocked = case.path("blocked");
    case.write(&blocked, "file");
    let output = case.run_env(
        &[],
        &[("VSMLRT_MODELS", &blocked.join("sub").to_string_lossy())],
    );
    assert_eq!(exited(&output), 1);
    assert!(
        stderr(&output).starts_with("mkdir: cannot create directory"),
        "{}",
        stderr(&output)
    );
    assert!(!case.argv_log().contains("cmd 7zz"));
}

#[test]
fn an_empty_version_argument_uses_the_default() {
    let case = fixture("empty-version");
    let destination = case.path("models");
    let output = case.run_env(&[""], &[("VSMLRT_MODELS", &destination.to_string_lossy())]);
    assert_eq!(exited(&output), 0);
    assert!(stdout(&output).starts_with("Downloading models v15.16 ..."));
}
