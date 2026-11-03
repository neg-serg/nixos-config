//! Hermetic tests for the `read_documents` port: fake fd/vicinae/zathura log
//! argv and stdin, and HOME is a per-case tree, so ~/dw is never the real one.

mod support;

use support::{exited, expected_argv, stderr, stdout, tool_script, Case};

const BIN: &str = env!("CARGO_BIN_EXE_read_documents");
const USAGE: &str = "\
read_documents: pick and open a document from ~/dw (vicinae dmenu -> zathura)
Usage: read_documents
";
const PROMPT: &str = "⟬doc⟭ ❯>";

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("fd", &tool_script("fd", "FD"));
    case.write_fake("vicinae", &tool_script("vicinae", "VICINAE"));
    case.write_fake("zathura", &tool_script("zathura", "ZATHURA"));
    case
}

fn fd_arguments(case: &Case) -> Vec<String> {
    let mut directory = case.home.clone();
    directory.push("dw/");
    vec![
        ".".to_string(),
        directory.to_string_lossy().into_owned(),
        "-d".to_string(),
        "1".to_string(),
        "-t".to_string(),
        "f".to_string(),
        "-e".to_string(),
        "pdf".to_string(),
        "-e".to_string(),
        "djvu".to_string(),
        "-e".to_string(),
        "epub".to_string(),
    ]
}

#[test]
fn help_prints_the_header_without_running_tools() {
    let case = fixture("read-documents-help");
    for argument in ["-h", "--help"] {
        let output = case.run(&[argument]);
        assert_eq!(exited(&output), 0, "{argument}");
        assert_eq!(stdout(&output), USAGE, "{argument}");
        assert_eq!(stderr(&output), "", "{argument}");
        assert_eq!(case.argv("fd"), "", "{argument}");
    }
}

#[test]
fn picks_a_document_and_opens_it_with_zathura() {
    let case = fixture("read-documents-pick");
    let output = case
        .command()
        .env("FAKE_FD_OUT", "a.pdf\nb.pdf\n")
        .env("FAKE_VICINAE_OUT", "b.pdf\n")
        .env("FAKE_ZATHURA_CODE", "3")
        .output()
        .expect("run read_documents");
    assert_eq!(exited(&output), 3);
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");

    let fd = fd_arguments(&case);
    let fd_refs: Vec<&str> = fd.iter().map(String::as_str).collect();
    assert_eq!(case.argv("fd"), expected_argv("fd", &fd_refs));
    assert_eq!(
        case.argv("vicinae"),
        expected_argv("vicinae", &["dmenu", "-p", PROMPT])
    );
    assert_eq!(case.stdin("vicinae"), "a.pdf\nb.pdf\n");
    assert_eq!(case.argv("zathura"), expected_argv("zathura", &["b.pdf"]));
}

#[test]
fn cancel_exits_one_without_opening_anything() {
    let case = fixture("read-documents-cancel");
    let output = case
        .command()
        .env("FAKE_FD_OUT", "a.pdf\n")
        .env("FAKE_VICINAE_OUT", "")
        .output()
        .expect("run read_documents");
    assert_eq!(exited(&output), 1);
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");
    assert_eq!(case.argv("zathura"), "");
}

#[test]
fn a_multi_line_selection_is_a_single_zathura_argument() {
    let case = fixture("read-documents-multiline");
    let output = case
        .command()
        .env("FAKE_FD_OUT", "a.pdf\nb.pdf\n")
        .env("FAKE_VICINAE_OUT", "a.pdf\nb.pdf\n")
        .output()
        .expect("run read_documents");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("zathura"),
        "zathura\nARG a.pdf\nb.pdf\n",
        "the newline must stay inside one argv element"
    );
}

#[test]
fn fd_failure_leaves_the_selection_empty() {
    let case = fixture("read-documents-fd-failure");
    let output = case
        .command()
        .env("FAKE_FD_CODE", "1")
        .env("FAKE_FD_ERR", "fd noise\n")
        .env("FAKE_VICINAE_OUT", "")
        .output()
        .expect("run read_documents");
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        "",
        "fd's stderr is redirected to /dev/null"
    );
    assert_eq!(case.stdin("vicinae"), "");
}

#[test]
fn a_missing_fd_warns_but_the_pipeline_still_runs() {
    let case = fixture("read-documents-no-fd");
    case.remove_fake("fd");
    let output = case
        .command()
        .env("FAKE_VICINAE_OUT", "")
        .output()
        .expect("run read_documents");
    assert_eq!(exited(&output), 1);
    assert_eq!(stderr(&output), "read_documents: fd not found\n");
    assert_eq!(case.stdin("vicinae"), "");
}

#[test]
fn a_missing_vicinae_reports_the_top_level_zsh_diagnostic() {
    let case = fixture("read-documents-no-vicinae");
    case.remove_fake("vicinae");
    let output = case
        .command()
        .env("FAKE_FD_OUT", "a.pdf\n")
        .output()
        .expect("run read_documents");
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        format!("read_documents: vicinae not found\n{BIN}:14: command not found: vicinae\n")
    );
    assert_eq!(case.argv("zathura"), "");
}

#[test]
fn a_missing_zathura_fails_with_127_after_a_selection() {
    let case = fixture("read-documents-no-zathura");
    case.remove_fake("zathura");
    let output = case
        .command()
        .env("FAKE_FD_OUT", "a.pdf\n")
        .env("FAKE_VICINAE_OUT", "a.pdf\n")
        .output()
        .expect("run read_documents");
    assert_eq!(exited(&output), 127);
    assert_eq!(
        stderr(&output),
        format!("read_documents: zathura not found\n{BIN}:15: command not found: zathura\n")
    );
}
