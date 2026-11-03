//! Hermetic tests for the `clip` port.

mod support;

use std::path::PathBuf;

use local_bin_desktop::helptext::CLIP_HELP;
use support::*;

const BIN: &str = env!("CARGO_BIN_EXE_clip");

fn videos(sandbox: &Sandbox) -> PathBuf {
    let directory = sandbox.home.join("vid/new");
    std::fs::create_dir_all(&directory).expect("create videos dir");
    directory
}

#[test]
fn help_variants_print_the_header() {
    let sandbox = Sandbox::new("clip-help");
    sandbox.install_default_fakes();
    for argument in ["help", "-h", "--help"] {
        let outcome = sandbox.run(BIN, &[argument]);
        assert_eq!(outcome.code, 0, "argument {argument}");
        assert_eq!(outcome.stdout, CLIP_HELP.as_bytes());
        assert_eq!(outcome.stderr, b"");
        assert!(sandbox.log().is_empty());
    }
}

#[test]
fn menu_decodes_the_picked_row() {
    let sandbox = Sandbox::new("clip-menu");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(
        BIN,
        &[],
        &[
            ("FAKE_CLIPHIST_LIST", "12: hello world"),
            ("FAKE_VICINAE_OUT", "12: hello world"),
            ("FAKE_CLIPHIST_DECODE", "hello world"),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(sandbox.last_clip(), b"hello world");
    assert_eq!(
        sandbox.calls("cliphist"),
        vec![
            call("cliphist", &["list"]),
            call("cliphist", &["decode", "12"]),
        ]
    );
    assert_eq!(
        sandbox.calls("vicinae"),
        vec![call("vicinae", &["dmenu", "-p", "clip ❯>"])]
    );
}

#[test]
fn cancelled_menu_exits_0() {
    let sandbox = Sandbox::new("clip-cancel");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(BIN, &[], &[("FAKE_VICINAE_OUT", "")]);
    assert_eq!(outcome.code, 0);
    assert!(sandbox.clipped().is_empty());
}

#[test]
fn pipe_runs_the_picked_command_over_the_selection() {
    let sandbox = Sandbox::new("clip-pipe");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(
        BIN,
        &["pipe"],
        &[
            ("FAKE_WLPASTE", "hello\nworld"),
            ("FAKE_VICINAE_OUT", "IFS= read -r x; printf '%s' \"$x\""),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(sandbox.last_clip(), b"hello");
    assert_eq!(
        sandbox.calls("vicinae"),
        vec![call("vicinae", &["dmenu", "-p", "❯>"])]
    );
    assert_eq!(
        str_of(&sandbox.read(&sandbox.vicinae_in)),
        "sort\ntac\n",
        "the preset list is the menu input"
    );
    assert_eq!(
        sandbox.calls("sh"),
        vec![call("sh", &["-c", "IFS= read -r x; printf '%s' \"$x\""])]
    );
}

#[test]
fn pipe_command_option_is_used_verbatim() {
    let sandbox = Sandbox::new("clip-command");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(
        BIN,
        &["pipe", "-c", "printf %s ok"],
        &[("FAKE_WLPASTE", "abc")],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(sandbox.last_clip(), b"ok");
    assert!(sandbox.calls("vicinae").is_empty(), "no menu for -c");
    assert_eq!(
        sandbox.calls("sh"),
        vec![call("sh", &["-c", "printf %s ok"])]
    );
}

#[test]
fn long_command_forms_are_accepted() {
    let sandbox = Sandbox::new("clip-longopts");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(
        BIN,
        &["pipe", "--command", "printf %s seen", "--paste"],
        &[("FAKE_WLPASTE", "abc")],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(sandbox.last_clip(), b"seen");
    // The paste prologue and epilogue send ctrl+c / ctrl+v.
    assert_eq!(
        sandbox.calls("wtype"),
        vec![
            call("wtype", &["-M", "ctrl", "-k", "c", "-m", "ctrl"]),
            call("wtype", &["-M", "ctrl", "-k", "v", "-m", "ctrl"]),
        ]
    );
}

#[test]
fn paste_mode_aborts_on_an_empty_clipboard() {
    let sandbox = Sandbox::new("clip-empty");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(BIN, &["pipe", "-p"], &[("FAKE_WLPASTE", "")]);
    assert_eq!(outcome.code, 1);
    assert_eq!(outcome.stderr, b"no input, aborting...\n");
    assert!(sandbox.clipped().is_empty());
    assert_eq!(
        sandbox.calls("sleep"),
        vec![call("sleep", &["0.05"])],
        "the prologue pause runs before the read"
    );
}

#[test]
fn paste_mode_copies_the_result_back() {
    let sandbox = Sandbox::new("clip-paste");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(
        BIN,
        &["pipe", "-p", "-c", "cat"],
        &[("FAKE_WLPASTE", "abc")],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(sandbox.last_clip(), b"abc");
    assert_eq!(
        sandbox.calls("sleep"),
        vec![call("sleep", &["0.05"]), call("sleep", &["0.05"])]
    );
    assert_eq!(sandbox.calls("wtype").len(), 2);
}

#[test]
fn double_dash_stops_option_parsing() {
    let sandbox = Sandbox::new("clip-dashdash");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(
        BIN,
        &["pipe", "--"],
        &[
            ("FAKE_WLPASTE", "abc"),
            ("FAKE_VICINAE_OUT", "printf %s chosen"),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(sandbox.last_clip(), b"chosen");
    assert_eq!(sandbox.calls("vicinae").len(), 1);
}

#[test]
fn youtube_dw_list_uses_the_picked_url_and_the_new_directory() {
    let sandbox = Sandbox::new("clip-ytlist");
    sandbox.install_default_fakes();
    sandbox.fake(
        "rg",
        "printf '%s\\n' '3: https://www.youtube.com/watch?v=abc'\n",
    );
    let directory = videos(&sandbox);
    let outcome = sandbox.run_env(
        BIN,
        &["youtube-dw-list"],
        &[
            (
                "FAKE_CLIPHIST_LIST",
                "3: https://www.youtube.com/watch?v=abc",
            ),
            ("FAKE_VICINAE_OUT", "3: https://www.youtube.com/watch?v=abc"),
            (
                "FAKE_CLIPHIST_DECODE",
                "https://www.youtube.com/watch?v=abc\n",
            ),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.calls("yt-dlp"),
        vec![call(
            "yt-dlp",
            &[
                "-f",
                "(bestvideo+bestaudio/best)",
                "https://www.youtube.com/watch?v=abc"
            ]
        )]
    );
    assert_eq!(
        str_of(&sandbox.read(&sandbox.ytdlp)),
        directory.to_str().unwrap(),
        "yt-dlp runs inside $XDG_VIDEOS_DIR/new"
    );
    assert_eq!(
        sandbox.calls("rg"),
        vec![call("rg", &["-E", "https.*(youtube|vimeo)\\\\.com"])],
        "the original's rg -E pattern is kept verbatim"
    );
}

#[test]
fn youtube_url_falls_back_to_grep_without_rg() {
    let sandbox = Sandbox::new("clip-grep");
    sandbox.install_default_fakes();
    std::fs::remove_file(sandbox.bin.join("rg")).expect("drop fake rg");
    sandbox.fake("grep", "printf '%s\\n' '5: https://vimeo.com/9'\n");
    videos(&sandbox);
    let outcome = sandbox.run_env(
        BIN,
        &["youtube-dw-list"],
        &[
            ("FAKE_VICINAE_OUT", "5: https://vimeo.com/9"),
            ("FAKE_CLIPHIST_DECODE", "https://vimeo.com/9\n"),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.calls("grep"),
        vec![call("grep", &["-E", "https.*(youtube|vimeo)\\\\.com"])]
    );
}

#[test]
fn youtube_dw_downloads_the_clipboard_url() {
    let sandbox = Sandbox::new("clip-ytdw");
    sandbox.install_default_fakes();
    let directory = videos(&sandbox);
    let outcome = sandbox.run_env(
        BIN,
        &["youtube-dw"],
        &[("FAKE_WLPASTE", "https://vimeo.com/1\n")],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.calls("yt-dlp"),
        vec![call(
            "yt-dlp",
            &["-f", "(bestvideo+bestaudio/best)", "https://vimeo.com/1"]
        )]
    );
    assert_eq!(
        str_of(&sandbox.read(&sandbox.ytdlp)),
        directory.to_str().unwrap()
    );
}

#[test]
fn empty_pick_still_runs_yt_dlp_with_an_empty_argument() {
    let sandbox = Sandbox::new("clip-ytempty");
    sandbox.install_default_fakes();
    videos(&sandbox);
    let outcome = sandbox.run_env(
        BIN,
        &["youtube-dw-list"],
        &[("FAKE_VICINAE_OUT", ""), ("FAKE_WLPASTE", "")],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.calls("yt-dlp"),
        vec![call("yt-dlp", &["-f", "(bestvideo+bestaudio/best)", ""])],
        "the failed command substitution becomes an empty argument"
    );
}

#[test]
fn missing_videos_directory_reports_cd() {
    let sandbox = Sandbox::new("clip-nocd");
    sandbox.install_default_fakes();
    let directory = sandbox.case.join("nope/new");
    let outcome = sandbox.run_env(
        BIN,
        &["youtube-dw"],
        &[(
            "XDG_VIDEOS_DIR",
            sandbox.case.join("nope").to_str().unwrap(),
        )],
    );
    assert_eq!(outcome.code, 1);
    let expected = format!(
        "{BIN}: line 126: cd: {}: No such file or directory\n",
        directory.display()
    );
    assert_eq!(outcome.stderr, expected.into_bytes());
}

#[test]
fn youtube_view_opens_the_scratchpad_and_pastes() {
    let sandbox = Sandbox::new("clip-view");
    sandbox.install_default_fakes();
    let outcome = sandbox.run(BIN, &["youtube-view"]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.calls("negwm"),
        vec![call("negwm", &["send", "scratchpad toggle youtube"])]
    );
    assert_eq!(sandbox.last_clip(), b"clip\n");
    assert_eq!(
        sandbox.calls("wtype"),
        vec![call("wtype", &["-M", "ctrl", "-k", "v", "-m", "ctrl"])]
    );
    assert_eq!(sandbox.calls("sleep"), vec![call("sleep", &["1s"])]);
}

#[test]
fn use_clipcat_routes_to_the_clipcat_menu() {
    let sandbox = Sandbox::new("clip-clipcat");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(BIN, &[], &[("USE_CLIPCAT", "true")]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.calls("clipcat-menu"),
        vec![call(
            "clipcat-menu",
            &[
                "-c",
                &format!(
                    "{}/.config/clipcat/clipcat-menu.toml",
                    sandbox.home.display()
                )
            ]
        )]
    );
    assert!(sandbox.calls("cliphist").is_empty());
}

#[test]
fn empty_use_clipcat_falls_back_to_cliphist() {
    let sandbox = Sandbox::new("clip-clipcat-empty");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(BIN, &[], &[("USE_CLIPCAT", ""), ("FAKE_VICINAE_OUT", "")]);
    assert_eq!(outcome.code, 0);
    assert!(sandbox.calls("clipcat-menu").is_empty());
    assert_eq!(sandbox.calls("cliphist").len(), 1);
}

#[test]
fn missing_sh_is_reported_like_the_shell() {
    let sandbox = Sandbox::new("clip-nosh");
    sandbox.install_default_fakes();
    std::fs::remove_file(sandbox.bin.join("sh")).expect("drop sh shim");
    let outcome = sandbox.run_env(BIN, &["pipe", "-c", "true"], &[("FAKE_WLPASTE", "abc")]);
    assert!(
        str_of(&outcome.stderr).contains(": line 79: sh: command not found\n"),
        "{}",
        str_of(&outcome.stderr)
    );
    assert_eq!(
        sandbox.clipped(),
        vec![Vec::<u8>::new()],
        "the empty transform result is still copied"
    );
}

#[test]
fn missing_wl_paste_is_reported() {
    let sandbox = Sandbox::new("clip-nowl");
    sandbox.install_default_fakes();
    std::fs::remove_file(sandbox.bin.join("wl-paste")).expect("drop fake");
    let outcome = sandbox.run(BIN, &["pipe", "-c", "true"]);
    assert!(
        str_of(&outcome.stderr).contains(": line 73: wl-paste: command not found\n"),
        "{}",
        str_of(&outcome.stderr)
    );
}
