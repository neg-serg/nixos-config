//! Hermetic tests for the `pl` port.
//!
//! Every external program is a fake first on an otherwise empty PATH. mpv's
//! stdout/stderr still go to the `~/tmp/mpv.log` the original redirects them
//! into, and HOME is a per-case tree, so no real socket, video directory or
//! music file is involved.

mod support;

use std::fs;

use support::{
    exited, expected_argv, fzf_script, playerctl_script, stderr, stdout, tool_script, xargs_script,
    Case,
};

const BIN: &str = env!("CARGO_BIN_EXE_pl");
const USAGE: &str = "\
pl: fuzzy-pick and play videos (fzf/vicinae dmenu -> mpv + vid-info)
Usage:
  pl [vicinae|dmenu|video|1st_level] [DIR]
  pl cmd <playerctl-args>
  pl vol {mute|unmute}
";
const PROMPT: &str = "⟬vid⟭ ❯>";

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("fd", &tool_script("fd", "FD"));
    case.write_fake("fzf", &fzf_script());
    case.write_fake("vicinae", &tool_script("vicinae", "VICINAE"));
    case.write_fake("wl-copy", &tool_script("wl-copy", "WL_COPY"));
    case.write_fake("mpv", &tool_script("mpv", "MPV"));
    case.write_fake("playerctl", &playerctl_script());
    case.write_fake("vset", &tool_script("vset", "VSET"));
    case.write_fake("amixer", &tool_script("amixer", "AMIXER"));
    case.write_fake("mkdir", &tool_script("mkdir", "MKDIR"));
    case.write_fake("find", &tool_script("find", "FIND"));
    case.write_fake("xargs", &xargs_script());
    case.write_fake("rg", &tool_script("rg", "RG"));
    fs::create_dir_all(case.path("home/vid")).expect("create video directory");
    fs::create_dir_all(case.path("home/vid/new")).expect("create new video directory");
    case.write(&case.path("home/vid/one.mp4"), "video");
    case.write(&case.path("home/vid/two.mp4"), "video");
    case
}

fn video_dir(case: &Case) -> String {
    case.path("home/vid").to_string_lossy().into_owned()
}

fn ipc_path(case: &Case) -> String {
    case.path("xdg/config/mpv/socket")
        .to_string_lossy()
        .into_owned()
}

fn fd_arguments(directory: &str) -> Vec<String> {
    [
        "-t",
        "f",
        "--hidden",
        "--follow",
        "-E",
        ".git",
        "-E",
        "node_modules",
        "-E",
        "*.srt",
        ".",
        directory,
    ]
    .iter()
    .map(|value| value.to_string())
    .collect()
}

fn assert_fd(case: &Case, expected: &[String]) {
    let references: Vec<&str> = expected.iter().map(String::as_str).collect();
    assert_eq!(case.argv("fd"), expected_argv("fd", &references));
}

#[test]
fn help_prints_the_header_without_running_tools() {
    let case = fixture("pl-help");
    for argument in ["-h", "--help"] {
        let output = case.run(&[argument]);
        assert_eq!(exited(&output), 0, "{argument}");
        assert_eq!(stdout(&output), USAGE, "{argument}");
        assert_eq!(stderr(&output), "", "{argument}");
        assert_eq!(case.argv("fd"), "", "{argument}");
    }
}

#[test]
fn fzf_selection_is_copied_and_played_with_absolute_paths() {
    let case = fixture("pl-fzf");
    let output = case
        .command()
        .env("FAKE_FD_OUT", "one.mp4\nsub/../two.mp4\n")
        .env("FAKE_FZF_EXTRA", "one.mp4\n/tmp/abs.mp4\n\nsub/../two.mp4")
        .output()
        .expect("run pl");
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");

    assert_fd(&case, &fd_arguments(&video_dir(&case)));
    assert_eq!(
        case.argv("fzf"),
        "fzf\nARG --multi\nARG --prompt\nARG ⟬vid⟭ ❯>\n"
    );
    assert_eq!(
        case.read_at(&case.logs.join("fzf.stdin.1")),
        "one.mp4\nsub/../two.mp4\n"
    );
    assert_eq!(
        case.stdin("wl-copy"),
        "one.mp4\n/tmp/abs.mp4\n\nsub/../two.mp4\n",
        "print -r -- \"$sel\" adds exactly one newline"
    );
    assert_eq!(
        case.argv("mpv"),
        expected_argv(
            "mpv",
            &[
                &format!("--input-ipc-server={}", ipc_path(&case)),
                "--vo=gpu",
                "--",
                &format!("{}/one.mp4", video_dir(&case)),
                "/tmp/abs.mp4",
                &format!("{}/sub/../two.mp4", video_dir(&case)),
            ]
        )
    );
    assert_eq!(
        case.argv("mkdir"),
        expected_argv(
            "mkdir",
            &["-p", "--", &case.path("home/tmp").to_string_lossy()]
        )
    );
}

#[test]
fn fzf_cancel_and_all_newline_selection_exit_zero() {
    for extra in ["", "\n\n"] {
        let case = fixture("pl-fzf-cancel");
        let output = case
            .command()
            .env("FAKE_FD_OUT", "one.mp4\n")
            .env("FAKE_FZF_EXTRA", extra)
            .output()
            .expect("run pl");
        assert_eq!(exited(&output), 0, "{extra:?}");
        assert_eq!(case.argv("mpv"), "", "{extra:?}");
        assert_eq!(case.argv("wl-copy"), "", "{extra:?}");
    }

    let case = fixture("pl-fzf-error");
    let output = case
        .command()
        .env("FAKE_FD_OUT", "one.mp4\n")
        .env("FAKE_FZF_CODE", "130")
        .output()
        .expect("run pl");
    assert_eq!(exited(&output), 0);
}

#[test]
fn dmenu_mode_always_consults_vicinae_for_a_single_candidate() {
    // zsh's `${#${(f)list}[@]}` yields the character count for a one-element
    // listing, so `> 1` is true and vicinae is called.
    let case = fixture("pl-dmenu-one");
    let output = case
        .command()
        .env("FAKE_FD_OUT", "one.mp4")
        .env("FAKE_VICINAE_OUT", "one.mp4")
        .args(["dmenu"])
        .output()
        .expect("run pl dmenu");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("vicinae"),
        expected_argv("vicinae", &["dmenu", "-p", PROMPT])
    );
    assert_eq!(case.stdin("vicinae"), "one.mp4\n");
    assert_eq!(
        case.argv("mpv"),
        expected_argv(
            "mpv",
            &[
                &format!("--input-ipc-server={}", ipc_path(&case)),
                "--vo=gpu",
                "--",
                &format!("{}/one.mp4", video_dir(&case)),
            ]
        )
    );
}

#[test]
fn dmenu_mode_handles_several_candidates_and_cancel() {
    let case = fixture("pl-dmenu-several");
    let output = case
        .command()
        .env("FAKE_FD_OUT", "one.mp4\ntwo.mp4\n")
        .env("FAKE_VICINAE_OUT", "two.mp4")
        .args(["vicinae"])
        .output()
        .expect("run pl dmenu");
    assert_eq!(exited(&output), 0);
    assert_eq!(case.stdin("vicinae"), "one.mp4\ntwo.mp4\n");
    assert_eq!(
        case.argv("mpv"),
        expected_argv(
            "mpv",
            &[
                &format!("--input-ipc-server={}", ipc_path(&case)),
                "--vo=gpu",
                "--",
                &format!("{}/two.mp4", video_dir(&case)),
            ]
        )
    );

    let case = fixture("pl-dmenu-cancel");
    let output = case
        .command()
        .env("FAKE_FD_OUT", "one.mp4\ntwo.mp4\n")
        .env("FAKE_VICINAE_OUT", "")
        .args(["dmenu"])
        .output()
        .expect("run pl dmenu");
    assert_eq!(exited(&output), 0);
    assert_eq!(case.argv("mpv"), "");
    assert_eq!(case.argv("wl-copy"), "");

    let case = fixture("pl-dmenu-empty");
    let output = case.run(&["dmenu"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(case.argv("vicinae"), "");
}

#[test]
fn video_mode_uses_its_legacy_socket_and_raw_selection() {
    let case = fixture("pl-video");
    let output = case
        .command()
        .env("FAKE_FD_OUT", "one.mp4")
        .env("FAKE_VICINAE_OUT", "one.mp4")
        .args(["video", &video_dir(&case)])
        .output()
        .expect("run pl video");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("fd"),
        expected_argv("fd", &["-t", "f", "-d", "1", ".", &video_dir(&case)])
    );
    assert_eq!(case.stdin("vicinae"), "one.mp4\n");
    assert_eq!(case.stdin("wl-copy"), "one.mp4\n");
    assert_eq!(
        case.argv("mpv"),
        expected_argv(
            "mpv",
            &["--input-ipc-server=/tmp/mpvsocket", "--vo=gpu", "one.mp4"]
        )
    );
}

#[test]
fn video_mode_defaults_to_home_vid_new() {
    let case = fixture("pl-video-default");
    let output = case
        .command()
        .env("FAKE_FD_OUT", "one.mp4")
        .env("FAKE_VICINAE_OUT", "")
        .args(["video"])
        .output()
        .expect("run pl video");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("fd"),
        expected_argv(
            "fd",
            &[
                "-t",
                "f",
                "-d",
                "1",
                ".",
                &case.path("home/vid/new").to_string_lossy(),
            ]
        )
    );
}

#[test]
fn first_level_limits_fd_depth() {
    let case = fixture("pl-first-level");
    let output = case
        .command()
        .env("FAKE_FD_OUT", "")
        .args(["1st_level", &video_dir(&case)])
        .output()
        .expect("run pl 1st_level");
    assert_eq!(exited(&output), 0);
    let mut expected = fd_arguments(&video_dir(&case));
    expected.insert(10, "1".to_string());
    expected.insert(10, "-d".to_string());
    assert_fd(&case, &expected);
}

#[test]
fn missing_fd_falls_back_to_rg() {
    let case = fixture("pl-rg");
    case.remove_fake("fd");
    let output = case
        .command()
        .env("FAKE_RG_OUT", "one.mp4\n")
        .env("FAKE_FZF_EXTRA", "one.mp4")
        .output()
        .expect("run pl");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("rg"),
        expected_argv(
            "rg",
            &[
                "--files",
                "--hidden",
                "--follow",
                "-g",
                "!{.git,node_modules}/*",
                "-g",
                "!*.srt",
                &video_dir(&case),
            ]
        )
    );
    assert_eq!(
        case.argv("mpv"),
        expected_argv(
            "mpv",
            &[
                &format!("--input-ipc-server={}", ipc_path(&case)),
                "--vo=gpu",
                "--",
                &format!("{}/one.mp4", video_dir(&case)),
            ]
        )
    );
}

#[test]
fn explicit_tilde_directory_is_expanded() {
    let case = fixture("pl-tilde");
    let output = case
        .command()
        .env("FAKE_FD_OUT", "")
        .args(["~/vid"])
        .output()
        .expect("run pl ~/vid");
    assert_eq!(exited(&output), 0);
    assert_fd(&case, &fd_arguments(&video_dir(&case)));
}

#[test]
fn xdg_videos_dir_is_the_default_directory() {
    let case = fixture("pl-xdg-videos");
    let output = case
        .command()
        .env("XDG_VIDEOS_DIR", video_dir(&case))
        .env("FAKE_FD_OUT", "")
        .output()
        .expect("run pl");
    assert_eq!(exited(&output), 0);
    assert_fd(&case, &fd_arguments(&video_dir(&case)));
}

#[test]
fn cmd_forwards_to_playerctl_and_propagates_the_status() {
    let case = fixture("pl-cmd");
    let output = case
        .command()
        .env("FAKE_PLAYERCTL_OUT", "playing\n")
        .env("FAKE_PLAYERCTL_CODE", "3")
        .args(["cmd", "play-pause"])
        .output()
        .expect("run pl cmd");
    assert_eq!(exited(&output), 3);
    assert_eq!(stdout(&output), "playing\n");
    assert_eq!(
        case.argv("playerctl"),
        expected_argv("playerctl", &["play-pause"])
    );
}

#[test]
fn a_missing_playerctl_reports_the_top_level_diagnostic() {
    let case = fixture("pl-no-playerctl");
    case.remove_fake("playerctl");
    let output = case.run(&["cmd", "next"]);
    assert_eq!(exited(&output), 127);
    assert_eq!(
        stderr(&output),
        format!("{BIN}:134: command not found: playerctl\n")
    );
}

#[test]
fn volume_uses_vset_and_falls_back_to_amixer() {
    let case = fixture("pl-vol-vset");
    let output = case.run(&["vol", "mute"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(case.argv("vset"), expected_argv("vset", &["0.0"]));
    assert_eq!(case.argv("amixer"), "");

    let case = fixture("pl-vol-fallback");
    let output = case
        .command()
        .env("FAKE_VSET_CODE", "1")
        .args(["vol", "unmute"])
        .output()
        .expect("run pl vol unmute");
    assert_eq!(exited(&output), 0);
    assert_eq!(case.argv("vset"), expected_argv("vset", &["1.0"]));
    assert_eq!(
        case.argv("amixer"),
        expected_argv("amixer", &["-q", "set", "Master", "65536", "unmute"])
    );

    let case = fixture("pl-vol-bogus");
    let output = case.run(&["vol", "bogus"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(case.argv("vset"), "");
    assert_eq!(case.argv("amixer"), "");
}

#[test]
fn a_missing_vset_is_diagnosed_before_the_amixer_fallback() {
    let case = fixture("pl-vol-no-vset");
    case.remove_fake("vset");
    let output = case.run(&["vol", "mute"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stderr(&output),
        format!("{BIN}:137: command not found: vset\n")
    );
    assert_eq!(
        case.argv("amixer"),
        expected_argv("amixer", &["-q", "set", "Master", "0", "mute"])
    );
}

#[test]
fn a_missing_fzf_warns_and_keeps_going() {
    let case = fixture("pl-no-fzf");
    case.remove_fake("fzf");
    let output = case
        .command()
        .env("FAKE_FD_OUT", "one.mp4\n")
        .output()
        .expect("run pl");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stderr(&output),
        "pl: missing fzf\npl_fzf:5: command not found: fzf\n"
    );
    assert_eq!(case.argv("mpv"), "");
}

#[test]
fn a_missing_mpv_is_reported_inside_mpv_log_with_127() {
    let case = fixture("pl-no-mpv");
    case.remove_fake("mpv");
    let output = case
        .command()
        .env("FAKE_FD_OUT", "one.mp4\n")
        .env("FAKE_FZF_EXTRA", "one.mp4")
        .output()
        .expect("run pl");
    assert_eq!(exited(&output), 127);
    assert_eq!(
        case.read_at(&case.path("home/tmp/mpv.log")),
        "mp:24: command not found: mpv\n"
    );
}

#[test]
fn a_missing_wl_copy_is_diagnosed_but_playback_continues() {
    let case = fixture("pl-no-wl-copy");
    case.remove_fake("wl-copy");
    let output = case
        .command()
        .env("FAKE_FD_OUT", "one.mp4\n")
        .env("FAKE_FZF_EXTRA", "one.mp4")
        .output()
        .expect("run pl");
    assert_eq!(exited(&output), 0);
    assert_eq!(stderr(&output), "pl_fzf:7: command not found: wl-copy\n");
    assert_eq!(
        case.argv("mpv"),
        expected_argv(
            "mpv",
            &[
                &format!("--input-ipc-server={}", ipc_path(&case)),
                "--vo=gpu",
                "--",
                &format!("{}/one.mp4", video_dir(&case)),
            ]
        )
    );
}

#[test]
fn vid_info_runs_for_picked_files_with_nul_separated_xargs() {
    let case = fixture("pl-vid-info-files");
    case.write_executable(
        &case.path("home/bin/vid-info"),
        &support::tool_script("vid-info", "VID_INFO"),
    );
    let output = case
        .command()
        .env("FAKE_FD_OUT", "one.mp4\n")
        .env("FAKE_FZF_EXTRA", "one.mp4")
        .output()
        .expect("run pl");
    assert_eq!(exited(&output), 0);
    case.wait_for_log("xargs");
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(3);
    while std::time::Instant::now() < deadline {
        if case
            .read_at(&case.logs.join("xargs.items"))
            .contains("ITEM ")
        {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(5));
    }
    assert_eq!(
        case.argv("xargs"),
        expected_argv(
            "xargs",
            &[
                "-0",
                "-n10",
                "-P",
                "10",
                &case.path("home/bin/vid-info").to_string_lossy(),
            ]
        )
    );
    assert_eq!(
        case.read_at(&case.logs.join("xargs.items")),
        format!("ITEM {}/one.mp4\n", video_dir(&case))
    );
}

#[test]
fn vid_info_runs_find_for_picked_directories() {
    let case = fixture("pl-vid-info-dirs");
    case.write_executable(
        &case.path("home/bin/vid-info"),
        &support::tool_script("vid-info", "VID_INFO"),
    );
    let output = case
        .command()
        .env("FAKE_FD_OUT", "one.mp4\n")
        .env("FAKE_FZF_EXTRA", &video_dir(&case))
        .output()
        .expect("run pl");
    assert_eq!(exited(&output), 0);
    case.wait_for_log("find");
    case.wait_for_log("xargs");
    assert_eq!(
        case.argv("find"),
        expected_argv(
            "find",
            &[
                "--",
                &video_dir(&case),
                "-maxdepth",
                "1",
                "-type",
                "f",
                "-print0",
            ]
        )
    );
    assert_eq!(
        case.argv("xargs"),
        expected_argv(
            "xargs",
            &[
                "-0",
                "-n10",
                "-P",
                "10",
                &case.path("home/bin/vid-info").to_string_lossy(),
            ]
        )
    );
}
