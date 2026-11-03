//! Hermetic tests for the `flacspec` port: `*.flac` selection, the
//! `${file%.*}.flac.png` naming, the `mkdir`/`sox`/`mv` argv and the shell
//! loop's exit-status rule.

mod support;

use support::{text, Sandbox};

const BIN: &str = env!("CARGO_BIN_EXE_flacspec");

const SOX: &str = r#"exit "${FAKE_SOX_CODE:-0}"
"#;
const MKDIR: &str = "exit \"${FAKE_MKDIR_CODE:-0}\"\n";
const MV: &str = "exit \"${FAKE_MV_CODE:-0}\"\n";

fn fixture(label: &str) -> Sandbox {
    let sandbox = Sandbox::new(label, BIN);
    sandbox.fake("mkdir", MKDIR);
    sandbox.fake("sox", SOX);
    sandbox.fake("mv", MV);
    sandbox
}

#[test]
fn help_prints_the_header_and_exits_zero() {
    let sandbox = fixture("help");
    for flag in ["-h", "--help"] {
        let outcome = sandbox.run(&[flag]);
        assert_eq!(outcome.code, 0);
        assert_eq!(
            text(&outcome.stdout),
            "flacspec: generate spectrograms for all .flac in current directory\n"
        );
        assert_eq!(outcome.stderr, b"");
    }
    assert_eq!(sandbox.log(), "");
}

#[test]
fn other_arguments_are_ignored() {
    let sandbox = fixture("ignored");
    sandbox.write("a.flac", b"fLaC");
    let outcome = sandbox.run(&["-x", "nomatch"]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.log_lines_for("sox"),
        vec!["sox\ta.flac\t-n\tspectrogram\t-o\ta.flac.png"]
    );
}

#[test]
fn no_flac_files_still_creates_the_directory() {
    let sandbox = fixture("empty");
    sandbox.write("notes.txt", b"x");
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 0);
    assert_eq!(outcome.stdout, b"");
    assert_eq!(outcome.stderr, b"");
    assert_eq!(
        sandbox.log_lines_for("mkdir"),
        vec!["mkdir\t-p\t--\tSpectrograms"]
    );
    assert!(sandbox.log_lines_for("sox").is_empty());
}

#[test]
fn one_file_is_rendered_and_moved() {
    let sandbox = fixture("one");
    sandbox.write("one.flac", b"fLaC");
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 0);
    assert_eq!(outcome.stdout, b"");
    assert_eq!(
        sandbox.log_lines_for("sox"),
        vec!["sox\tone.flac\t-n\tspectrogram\t-o\tone.flac.png"]
    );
    assert_eq!(
        sandbox.log_lines_for("mv"),
        vec!["mv\t--\tone.flac.png\tSpectrograms/"]
    );
}

#[test]
fn dotted_names_keep_the_stem_and_hidden_files_are_skipped() {
    let sandbox = fixture("names");
    sandbox.write("a.b.flac", b"fLaC");
    sandbox.write(".hidden.flac", b"fLaC");
    sandbox.write("upper.FLAC", b"fLaC");
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.log_lines_for("sox"),
        vec!["sox\ta.b.flac\t-n\tspectrogram\t-o\ta.b.flac.png"]
    );
}

#[test]
fn directories_matching_the_glob_are_skipped() {
    let sandbox = fixture("dir-entry");
    sandbox.write("dir.flac/inner.txt", b"x");
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 0);
    assert!(sandbox.log_lines_for("sox").is_empty());
    assert!(sandbox.log_lines_for("mv").is_empty());
}

#[test]
fn files_are_processed_in_byte_order() {
    let sandbox = fixture("order");
    sandbox.write("b.flac", b"fLaC");
    sandbox.write("a.flac", b"fLaC");
    sandbox.write("c.flac", b"fLaC");
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 0);
    let sox = sandbox.log_lines_for("sox");
    let names: Vec<&str> = sox
        .iter()
        .map(|line| line.split('\t').nth(1).unwrap())
        .collect();
    assert_eq!(names, vec!["a.flac", "b.flac", "c.flac"]);
}

#[test]
fn a_failing_sox_skips_mv_and_sets_the_status() {
    let sandbox = fixture("sox-fail");
    sandbox.write("fail.flac", b"fLaC");
    let outcome = sandbox.run_env(&[], &[("FAKE_SOX_CODE", "7")]);
    assert_eq!(outcome.code, 7);
    assert!(sandbox.log_lines_for("mv").is_empty());
}

#[test]
fn a_failing_mv_sets_the_status() {
    let sandbox = fixture("mv-fail");
    sandbox.write("one.flac", b"fLaC");
    let outcome = sandbox.run_env(&[], &[("FAKE_MV_CODE", "4")]);
    assert_eq!(outcome.code, 4);
}

#[test]
fn a_failing_mkdir_does_not_abort_the_loop() {
    let sandbox = fixture("mkdir-fail");
    sandbox.write("one.flac", b"fLaC");
    let outcome = sandbox.run_env(&[], &[("FAKE_MKDIR_CODE", "1")]);
    assert_eq!(outcome.code, 0);
    assert_eq!(sandbox.log_lines_for("sox").len(), 1);
}

#[test]
fn missing_sox_warns_and_reports_the_spawn() {
    let sandbox = fixture("no-sox");
    sandbox.remove_fake("sox");
    sandbox.write("one.flac", b"fLaC");
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 127);
    let stderr = text(&outcome.stderr);
    assert!(stderr.starts_with("flacspec: missing sox\n"), "{stderr}");
    assert!(
        stderr.contains(&format!(
            "{}: line 17: sox: command not found\n",
            sandbox.program().display()
        )),
        "{stderr}"
    );
    assert!(sandbox.log_lines_for("mv").is_empty());
}
