//! Hermetic tests for the `mpd_del_album` port.
//!
//! mpc and mv are fakes; the `/one/music` path and the trash destination are
//! only strings in the argv log, so the real queue and trash are untouched.

mod support;

use support::{exited, expected_argv, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_mpd_del_album");
const USAGE: &str = "\
Usage: mpd_del_album [ARTIST]
Remove current album (as detected by mpc) by moving its directory to ~/trash/music/.
";

const MPC: &str = r#"#!/bin/sh
{ printf 'mpc\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/mpc.argv"
case "$2" in
  %artist%) printf '%s' "${FAKE_MPC_ARTIST-}" ;;
  %file%) printf '%s' "${FAKE_MPC_FILE-}" ;;
esac
exit "${FAKE_MPC_CODE:-0}"
"#;

const MV: &str = r#"#!/bin/sh
{ printf 'mv\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/mv.argv"
printf '%s' "${FAKE_MV_OUT-}"
printf '%s' "${FAKE_MV_ERR-}" >&2
exit "${FAKE_MV_CODE:-0}"
"#;

fn case(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("mpc", MPC);
    case.write_fake("mv", MV);
    case
}

fn prompt(album: &str) -> String {
    format!("Remove:\n \u{1b}[38;5;30m{album}\u{1b}[m ? [y/N] ")
}

fn run_with_answer(
    case: &Case,
    input: &[u8],
    environment: &[(&str, &str)],
) -> std::process::Output {
    use std::io::Write;
    let mut command = case.command();
    for (name, value) in environment {
        command.env(name, value);
    }
    let mut child = command
        .stdin(std::process::Stdio::piped())
        .spawn()
        .expect("spawn mpd_del_album");
    child
        .stdin
        .take()
        .expect("piped stdin")
        .write_all(input)
        .expect("write answer");
    child.wait_with_output().expect("wait for mpd_del_album")
}

#[test]
fn help_uses_the_invoked_basename() {
    let case = case("mpd-help");
    for argument in ["-h", "--help"] {
        let output = case.run(&[argument]);
        assert_eq!(exited(&output), 0);
        assert_eq!(stdout(&output), USAGE);
        assert_eq!(stderr(&output), "");
        assert_eq!(case.argv("mpc"), "");
    }
}

#[test]
fn cancel_reads_both_mpc_fields_and_prints_the_broken_warn() {
    let case = case("mpd-cancel");
    let output = case
        .command()
        .env("FAKE_MPC_ARTIST", "The Artist\n")
        .env("FAKE_MPC_FILE", "The Artist/The Album/01.flac\n")
        .stdin(std::process::Stdio::piped())
        .spawn()
        .and_then(|mut child| {
            use std::io::Write;
            child
                .stdin
                .take()
                .expect("piped stdin")
                .write_all(b"n\n")
                .expect("write answer");
            child.wait_with_output()
        })
        .expect("run mpd_del_album");
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), prompt("The Artist/The Album"));
    assert_eq!(
        stderr(&output),
        format!("{BIN}:29: command not found: warn\n")
    );
    let mut expected = expected_argv("mpc", &["--format", "%artist%"]);
    expected.push_str(&expected_argv("mpc", &["--format", "%file%"]));
    assert_eq!(case.argv("mpc"), expected);
    assert_eq!(case.argv("mv"), "");
}

#[test]
fn a_yes_moves_the_album_with_the_original_argv() {
    let case = case("mpd-yes");
    let output = case
        .command()
        .env("FAKE_MPC_ARTIST", "The Artist\n")
        .env("FAKE_MPC_FILE", "The Artist/The Album/01.flac\n")
        .stdin(std::process::Stdio::piped())
        .spawn()
        .and_then(|mut child| {
            use std::io::Write;
            child
                .stdin
                .take()
                .expect("piped stdin")
                .write_all(b"y\n")
                .expect("write answer");
            child.wait_with_output()
        })
        .expect("run mpd_del_album");
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), prompt("The Artist/The Album"));
    assert_eq!(stderr(&output), "");
    let destination = format!("{}/trash/music/", case.home.display());
    assert_eq!(
        case.argv("mv"),
        expected_argv(
            "mv",
            &["-v", "/one/music/The Artist/The Album", &destination]
        )
    );
}

#[test]
fn an_artist_argument_skips_the_artist_query() {
    let case = case("mpd-artist-arg");
    let output = case
        .command()
        .env("FAKE_MPC_FILE", "A/B/01.flac\n")
        .arg("Somebody")
        .spawn()
        .and_then(|mut child| {
            // stdin is null in command(); the empty answer cancels.
            child.wait_with_output()
        })
        .expect("run mpd_del_album");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("mpc"),
        expected_argv("mpc", &["--format", "%file%"])
    );
}

#[test]
fn album_paths_keep_the_original_perl_semantics() {
    let cases = [
        ("Artist/Album/01.flac\n", "Artist/Album"),
        ("Album/01.flac\n", "Album"),
        ("01.flac\n", "01.flac"),
        ("Artist/Album/\n", "Artist"),
        ("/root.flac\n", "/root.flac"),
        ("a/b/c\n", "a/b"),
        ("Artist/With Space/01.flac\n", "Artist/With Space"),
        ("only\n", "only"),
    ];
    for (file, album) in cases {
        let case = case("mpd-album");
        let output = case
            .command()
            .env("FAKE_MPC_ARTIST", "A\n")
            .env("FAKE_MPC_FILE", file)
            .spawn()
            .and_then(|child| child.wait_with_output())
            .expect("run mpd_del_album");
        assert_eq!(exited(&output), 0, "{file:?}");
        assert_eq!(stdout(&output), prompt(album), "{file:?}");
    }
}

#[test]
fn the_first_line_of_the_mpc_output_wins() {
    let case = case("mpd-first-line");
    let output = case
        .command()
        .env("FAKE_MPC_FILE", "A/B/01.flac\nC/D/02.flac\n")
        .spawn()
        .and_then(|child| child.wait_with_output())
        .expect("run mpd_del_album");
    assert_eq!(stdout(&output), prompt("A/B"));
}

#[test]
fn read_matches_zsh_ifs_and_backslash_rules() {
    for (input, confirms) in [
        (b"  y  \n".as_slice(), false),
        (b"y\t\n".as_slice(), true),
        (b"\\y\n".as_slice(), true),
        (b"y\\\n\n".as_slice(), true),
        (b"y\r\n".as_slice(), false),
    ] {
        let case = case("mpd-read");
        let output = run_with_answer(&case, input, &[("FAKE_MPC_FILE", "A/B/01.flac\n")]);
        assert_eq!(exited(&output), 0, "{input:?}");
        if confirms {
            assert!(
                !case.argv("mv").is_empty(),
                "{input:?} should confirm, stderr={:?}",
                stderr(&output)
            );
        } else {
            assert!(case.argv("mv").is_empty(), "{input:?} should cancel");
        }
    }
}

#[test]
fn uppercase_y_does_not_confirm() {
    let case = case("mpd-uppercase-y");
    let output = case
        .command()
        .env("FAKE_MPC_FILE", "A/B/01.flac\n")
        .stdin(std::process::Stdio::piped())
        .spawn()
        .and_then(|mut child| {
            use std::io::Write;
            child
                .stdin
                .take()
                .expect("piped stdin")
                .write_all(b"Y\n")
                .expect("write answer");
            child.wait_with_output()
        })
        .expect("run mpd_del_album");
    assert_eq!(exited(&output), 0);
    assert_eq!(case.argv("mv"), "");
    assert!(stderr(&output).contains("command not found: warn"));
}

#[test]
fn eof_is_an_empty_answer() {
    let case = case("mpd-eof");
    let output = case
        .command()
        .env("FAKE_MPC_FILE", "A/B/01.flac\n")
        .output()
        .expect("run mpd_del_album");
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), prompt("A/B"));
    assert_eq!(case.argv("mv"), "");
}

#[test]
fn a_failing_mpc_leaves_an_empty_album() {
    let case = case("mpd-mpc-fails");
    let output = case
        .command()
        .env("FAKE_MPC_CODE", "1")
        .stdin(std::process::Stdio::piped())
        .spawn()
        .and_then(|mut child| {
            use std::io::Write;
            child
                .stdin
                .take()
                .expect("piped stdin")
                .write_all(b"y\n")
                .expect("write answer");
            child.wait_with_output()
        })
        .expect("run mpd_del_album");
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), prompt(""));
    assert_eq!(
        case.argv("mv"),
        expected_argv(
            "mv",
            &[
                "-v",
                "/one/music/",
                &format!("{}/trash/music/", case.home.display())
            ]
        )
    );
}

#[test]
fn a_failing_mv_still_exits_zero() {
    let case = case("mpd-mv-fails");
    let output = case
        .command()
        .env("FAKE_MPC_FILE", "A/B/01.flac\n")
        .env("FAKE_MV_CODE", "1")
        .stdin(std::process::Stdio::piped())
        .spawn()
        .and_then(|mut child| {
            use std::io::Write;
            child
                .stdin
                .take()
                .expect("piped stdin")
                .write_all(b"y\n")
                .expect("write answer");
            child.wait_with_output()
        })
        .expect("run mpd_del_album");
    assert_eq!(exited(&output), 0);
    assert!(stderr(&output).is_empty());
}

#[test]
fn a_missing_mv_is_diagnosed_and_still_exits_zero() {
    let case = case("mpd-missing-mv");
    case.remove_fake("mv");
    let output = case
        .command()
        .env("FAKE_MPC_FILE", "A/B/01.flac\n")
        .stdin(std::process::Stdio::piped())
        .spawn()
        .and_then(|mut child| {
            use std::io::Write;
            child
                .stdin
                .take()
                .expect("piped stdin")
                .write_all(b"y\n")
                .expect("write answer");
            child.wait_with_output()
        })
        .expect("run mpd_del_album");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stderr(&output),
        format!("{BIN}:31: command not found: mv\n")
    );
}

#[test]
fn the_usage_has_no_leading_path() {
    // Guard against accidentally embedding the build path in the usage text.
    assert!(USAGE.starts_with("Usage: mpd_del_album "));
}
