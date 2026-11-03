//! Hermetic tests for the `pdf2md` port: the help gate, the `-o`/`--output=`
//! rewriting and the pass-through of every other docling argument. The fake
//! `docling` records argv and the inherited `HF_HOME`.

mod support;

use support::{exited, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_pdf2md");

const DOCLING: &str = r#"#!/bin/sh
printf 'cmd docling\n' >> "$FAKE_ARGV_LOG"
for argument in "$@"; do printf '  %s\n' "$argument" >> "$FAKE_ARGV_LOG"; done
printf '  HF_HOME %s\n' "${HF_HOME-unset}" >> "$FAKE_ARGV_LOG"
printf 'docling-out\n'
printf 'docling-err\n' >&2
exit "${FAKE_DOCLING_CODE:-0}"
"#;

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("docling", DOCLING);
    case
}

#[test]
fn help_is_the_default_for_no_arguments_and_for_the_flag() {
    let case = fixture("help");
    for arguments in [Vec::<&str>::new(), vec!["-h"], vec!["--help"]] {
        let output = case.run(&arguments);
        assert_eq!(exited(&output), 0);
        assert_eq!(stderr(&output), "");
        let text = stdout(&output);
        assert!(text.starts_with(
            "pdf2md: PDF/DOCX/HTML/images → Markdown through docling, entirely from the\n"
        ));
        assert!(
            text.ends_with("  pdf2md --to json file.pdf    # every docling flag passes through\n")
        );
        assert!(!case.argv_log().contains("cmd docling"));
    }
}

#[test]
fn output_directory_forms_are_rewritten() {
    let case = fixture("output");
    let output = case.run(&["-o", "out/", "a.pdf", "b.pdf"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv_log()
            .lines()
            .take(6)
            .collect::<Vec<_>>()
            .join("\n"),
        "cmd docling\n  --to\n  md\n  --output\n  out/\n  a.pdf"
    );
    assert!(case.argv_log().contains("  b.pdf"));

    let equals = fixture("output-equals");
    let _ = equals.run(&["--output=out", "a.pdf"]);
    assert!(equals
        .argv_log()
        .contains("cmd docling\n  --to\n  md\n  --output\n  out\n  a.pdf\n"));
}

#[test]
fn two_dash_output_without_a_value_is_a_usage_error() {
    let case = fixture("missing-output");
    let output = case.run(&["-o"]);
    assert_eq!(exited(&output), 2);
    assert_eq!(stderr(&output), "pdf2md: -o needs a directory\n");
    assert_eq!(case.argv_log(), "");

    let case = fixture("missing-output-long");
    let output = case.run(&["--output"]);
    assert_eq!(exited(&output), 2);
    assert_eq!(stderr(&output), "pdf2md: -o needs a directory\n");
}

#[test]
fn every_other_flag_is_forwarded_after_the_explicit_markdown_mode() {
    let case = fixture("passthrough");
    let output = case.run(&["--to", "json", "--from", "html", "f.pdf"]);
    assert_eq!(exited(&output), 0);
    let hf_home = if std::path::Path::new("/zero/ai/ocr").is_dir() {
        "/zero/ai/ocr"
    } else {
        "unset"
    };
    assert_eq!(
        case.argv_log().lines().take(9).collect::<Vec<_>>().join("\n"),
        format!("cmd docling\n  --to\n  md\n  --to\n  json\n  --from\n  html\n  f.pdf\n  HF_HOME {hf_home}")
    );
}

#[test]
fn docling_status_and_streams_are_forwarded() {
    let case = fixture("status");
    let output = case.run_env(&["a.pdf"], &[("FAKE_DOCLING_CODE", "7")]);
    assert_eq!(exited(&output), 7);
    assert_eq!(stdout(&output), "docling-out\n");
    assert_eq!(stderr(&output), "docling-err\n");
}

#[test]
fn a_missing_docling_exits_127() {
    let case = fixture("missing");
    case.remove_fake("docling");
    let output = case.run(&["a.pdf"]);
    assert_eq!(exited(&output), 127);
}

#[test]
fn hf_home_is_preserved_and_only_defaulted_when_the_asset_tree_exists() {
    let case = fixture("hf-home");
    let _ = case.run_env(&["a.pdf"], &[("HF_HOME", "custom")]);
    assert!(case.argv_log().contains("  HF_HOME custom"));

    let case = fixture("hf-default");
    let _ = case.run(&["a.pdf"]);
    let expected = if std::path::Path::new("/zero/ai/ocr").is_dir() {
        "  HF_HOME /zero/ai/ocr"
    } else {
        "  HF_HOME unset"
    };
    assert!(case.argv_log().contains(expected), "{}", case.argv_log());
}

#[test]
fn help_is_only_recognized_as_the_first_argument() {
    let case = fixture("help-late");
    let output = case.run(&["f.pdf", "--help"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv_log()
            .lines()
            .take(5)
            .collect::<Vec<_>>()
            .join("\n"),
        "cmd docling\n  --to\n  md\n  f.pdf\n  --help"
    );
}

#[test]
fn an_empty_output_value_is_forwarded_as_empty() {
    let case = fixture("empty-output");
    let _ = case.run(&["-o", "", "a.pdf"]);
    assert!(case
        .argv_log()
        .contains("cmd docling\n  --to\n  md\n  --output\n  \n  a.pdf\n"));
}
