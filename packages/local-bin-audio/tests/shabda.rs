//! Hermetic tests for the `shabda` port: the bash-`getopts` behaviour, the
//! Tidal/Strudel line spelling, the append state file, the clipboard payload
//! and the browser spawn.

mod support;

use support::{text, Sandbox};

const BIN: &str = env!("CARGO_BIN_EXE_shabda");
const BASE: &str = "https://shabda.ndre.gr";
const TIDAL: &str = "!reslist \"https://shabda.ndre.gr/amen.json?licenses=by,cc0,by-nc\"";
const STRUDEL: &str = "samples('https://shabda.ndre.gr/808.json?strudel=1&licenses=by,cc0,by-nc')";

const VIVALDI: &str = "exit 0\n";
const WLCOPY: &str = "IFS= read -r line || true\nprintf '%s' \"$line\" > \"$HOME/clip\"\n";
const MKDIR: &str = "exit \"${FAKE_MKDIR_CODE:-0}\"\n";
const GREP: &str = "exit \"${FAKE_GREP_CODE:-1}\"\n";

fn fixture(label: &str) -> Sandbox {
    let sandbox = Sandbox::new(label, BIN);
    sandbox.fake("vivaldi", VIVALDI);
    sandbox.fake("wl-copy", WLCOPY);
    sandbox.fake("mkdir", MKDIR);
    sandbox.fake("grep", GREP);
    sandbox
}

fn sample_path(sandbox: &Sandbox) -> std::path::PathBuf {
    sandbox.home.join("notes/music/tidal/shabda-samples.json")
}

#[test]
fn no_pack_opens_the_browser() {
    let sandbox = fixture("no-pack");
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        text(&outcome.stdout),
        "Shabda opened in the browser: https://shabda.ndre.gr\n\
         Pick a pack there, then run:  shabda <pack>\n"
    );
    assert_eq!(outcome.stderr, b"");
    assert_eq!(
        sandbox.wait_log(&format!("vivaldi\t{BASE}")),
        format!("vivaldi\t{BASE}\n")
    );
}

#[test]
fn list_only_prints_the_tidal_line() {
    let sandbox = fixture("tidal");
    let outcome = sandbox.run(&["-l", "amen"]);
    assert_eq!(outcome.code, 0);
    assert_eq!(text(&outcome.stdout), format!("{TIDAL}\n"));
    assert_eq!(outcome.stderr, b"");
    assert_eq!(sandbox.log(), "");
}

#[test]
fn list_only_prints_the_strudel_line() {
    let sandbox = fixture("strudel");
    let outcome = sandbox.run(&["-s", "-l", "808"]);
    assert_eq!(outcome.code, 0);
    assert_eq!(text(&outcome.stdout), format!("{STRUDEL}\n"));
}

#[test]
fn combined_and_terminated_options_are_parsed_like_getopts() {
    let sandbox = fixture("options");
    let outcome = sandbox.run(&["-sl", "amen"]);
    assert_eq!(
        text(&outcome.stdout),
        "samples('https://shabda.ndre.gr/amen.json?strudel=1&licenses=by,cc0,by-nc')\n"
    );

    let outcome = sandbox.run(&["--", "-x"]);
    assert!(
        text(&outcome.stdout).starts_with(
            "copied: !reslist \"https://shabda.ndre.gr/-x.json?licenses=by,cc0,by-nc\"\n"
        ),
        "{}",
        text(&outcome.stdout)
    );

    // Options after the first operand are ignored: this is a pack named "-s".
    let outcome = sandbox.run(&["amen", "-s"]);
    assert!(
        text(&outcome.stdout).starts_with(&format!("copied: {TIDAL}\n")),
        "{}",
        text(&outcome.stdout)
    );
}

#[test]
fn illegal_options_print_the_bash_diagnostic_and_exit_two() {
    let sandbox = fixture("illegal");
    for (argument, option) in [("-x", "x"), ("-h", "h")] {
        let outcome = sandbox.run(&[argument]);
        assert_eq!(outcome.code, 2);
        assert_eq!(outcome.stdout, b"");
        assert_eq!(
            text(&outcome.stderr),
            format!(
                "{}: illegal option -- {option}\nusage: {} [-s|-l|-a] [pack]\n",
                sandbox.program().display(),
                sandbox.program().display()
            )
        );
    }
}

#[test]
fn clipboard_copy_is_the_tidal_line() {
    let sandbox = fixture("clipboard");
    let outcome = sandbox.run(&["amen"]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        text(&outcome.stdout),
        format!("copied: {TIDAL}\nShabda opened (paste the copied line into Tidal/Strudel).\n")
    );
    assert_eq!(text(&sandbox.read_home("clip")), TIDAL);
    assert_eq!(sandbox.log_lines_for("wl-copy"), vec!["wl-copy"]);
    sandbox.wait_log(&format!("vivaldi\t{BASE}"));
}

#[test]
fn without_wl_copy_the_line_is_printed() {
    let sandbox = fixture("no-wlcopy");
    sandbox.remove_fake("wl-copy");
    let outcome = sandbox.run(&["amen"]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        text(&outcome.stdout),
        format!("{TIDAL}\nShabda opened (paste the copied line into Tidal/Strudel).\n")
    );
    assert_eq!(sandbox.read_home("clip"), b"");
}

#[test]
fn a_failing_clipboard_tool_stops_the_script() {
    let sandbox = fixture("clipboard-fail");
    sandbox.fake("wl-copy", "exit 3\n");
    let outcome = sandbox.run(&["amen"]);
    assert_eq!(outcome.code, 3);
    assert_eq!(outcome.stdout, b"");
    assert!(!sandbox.log().contains("vivaldi\t"));
}

#[test]
fn append_creates_the_list_and_prints_the_path() {
    let sandbox = fixture("append-new");
    sandbox.write_home("notes/music/tidal/.keep", b"");
    let outcome = sandbox.run(&["-a", "amen"]);
    assert_eq!(outcome.code, 0);
    let file = sample_path(&sandbox);
    assert_eq!(
        text(&outcome.stdout),
        format!("appended to {}\n", file.display())
    );
    assert_eq!(
        text(&sandbox.read_home("notes/music/tidal/shabda-samples.json")),
        format!("{TIDAL}\n")
    );
    assert_eq!(
        sandbox.log_lines_for("mkdir"),
        vec![format!(
            "mkdir\t-p\t{}/notes/music/tidal",
            sandbox.home.display()
        )]
    );
    assert!(sandbox.log_lines_for("grep").is_empty());
}

#[test]
fn an_existing_pack_is_not_appended_twice() {
    let sandbox = fixture("append-existing");
    let file = sandbox.write_home(
        "notes/music/tidal/shabda-samples.json",
        format!("{TIDAL}\n").as_bytes(),
    );
    let outcome = sandbox.run_env(&["-a", "amen"], &[("FAKE_GREP_CODE", "0")]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        text(&outcome.stdout),
        format!("already in {}\n", file.display())
    );
    assert_eq!(
        sandbox.log_lines_for("grep"),
        vec![format!("grep\t-q\tamen.json\t{}", file.display())]
    );
}

#[test]
fn a_pack_missing_from_the_list_is_appended() {
    let sandbox = fixture("append-miss");
    sandbox.write_home(
        "notes/music/tidal/shabda-samples.json",
        b"!reslist \"https://shabda.ndre.gr/techno.json?licenses=by,cc0,by-nc\"\n",
    );
    let outcome = sandbox.run(&["-a", "amen"]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        text(&sandbox.read_home("notes/music/tidal/shabda-samples.json")),
        format!("!reslist \"https://shabda.ndre.gr/techno.json?licenses=by,cc0,by-nc\"\n{TIDAL}\n")
    );
}

#[test]
fn append_wins_over_list_only() {
    let sandbox = fixture("append-wins");
    sandbox.write_home(
        "notes/music/tidal/shabda-samples.json",
        b"!reslist \"https://shabda.ndre.gr/techno.json?licenses=by,cc0,by-nc\"\n",
    );
    let outcome = sandbox.run(&["-a", "-l", "amen"]);
    assert_eq!(outcome.code, 0);
    assert!(text(&outcome.stdout).starts_with("appended to "));
    assert!(sandbox.log().contains("grep\t-q\tamen.json\t"));
}

#[test]
fn a_failing_mkdir_stops_the_append() {
    let sandbox = fixture("mkdir-fail");
    sandbox.write_home("notes/music/tidal/.keep", b"");
    let outcome = sandbox.run_env(&["-a", "amen"], &[("FAKE_MKDIR_CODE", "4")]);
    assert_eq!(outcome.code, 4);
    assert_eq!(outcome.stdout, b"");
    assert_eq!(
        sandbox.read_home("notes/music/tidal/shabda-samples.json"),
        b""
    );
}

#[test]
fn a_missing_browser_is_silent() {
    let sandbox = fixture("no-browser");
    sandbox.remove_fake("vivaldi");
    let outcome = sandbox.run(&["-l", "amen"]);
    assert_eq!(outcome.code, 0);
    let outcome = sandbox.run(&["amen"]);
    assert_eq!(outcome.code, 0);
    assert!(text(&outcome.stdout).contains("Shabda opened"));
}
