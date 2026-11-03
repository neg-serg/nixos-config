//! Hermetic tests for the `music-rename` port.
//!
//! albumdetails/find/realpath/mv/ren/rmdir/nc/socat are fakes; XDG_MUSIC_DIR
//! points into the per-case temporary tree and the fake `mv` is dry, so nothing
//! is renamed on the host. The naming rules are asserted through the exact
//! `mv -i -- SRC DST` argv the original builds.

mod support;

use std::fs;

use support::{exited, expected_argv, stderr, stdout, tool_script, Case};

const BIN: &str = env!("CARGO_BIN_EXE_music-rename");
const USAGE: &str = "\
music-rename: rename music files/directories to a normalized scheme
Usage: music-rename [options] PATH...
  Renames files/dirs in-place following custom rules. Use with care.
";

const REALPATH: &str = r#"#!/bin/sh
{ printf 'realpath\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/realpath.argv"
: > "$FAKE_LOG_DIR/realpath.stdin"
while IFS= read -r line || [ -n "$line" ]; do printf '%s\n' "$line" >> "$FAKE_LOG_DIR/realpath.stdin"; done
printf '%s' "$3"
"#;

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("albumdetails", &tool_script("albumdetails", "ALBUMDETAILS"));
    case.write_fake("find", &tool_script("find", "FIND"));
    case.write_fake("realpath", REALPATH);
    case.write_fake("mv", &tool_script("mv", "MV"));
    case.write_fake("ren", &tool_script("ren", "REN"));
    case.write_fake("rmdir", &tool_script("rmdir", "RMDIR"));
    case.write_fake("nc", &tool_script("nc", "NC"));
    case.write_fake("socat", &tool_script("socat", "SOCAT"));
    fs::create_dir_all(case.path("case/ArtistDir")).expect("create case tree");
    fs::create_dir_all(case.path("music-ren")).expect("create music dir");
    case.write(&case.path("case/ArtistDir/track.flac"), "audio");
    case
}

fn music_dir(case: &Case) -> String {
    case.path("music-ren").to_string_lossy().into_owned()
}

fn track(case: &Case) -> String {
    case.path("case/ArtistDir/track.flac")
        .to_string_lossy()
        .into_owned()
}

fn artist_dir(case: &Case) -> String {
    case.path("case/ArtistDir").to_string_lossy().into_owned()
}

fn destination(case: &Case, name: &str) -> String {
    format!("{}/{}", music_dir(case), name)
}

fn full() -> &'static str {
    "Artist: The Artist\nYear: 2026\nAlbum: The Album"
}

fn run_with_data(case: &Case, arguments: &[&str], data: &str) -> std::process::Output {
    case.command()
        .env("XDG_MUSIC_DIR", music_dir(case))
        .env("FAKE_ALBUMDETAILS_OUT", data)
        .args(arguments)
        .output()
        .expect("run music-rename")
}

#[test]
fn help_prints_the_header_without_running_tools() {
    let case = fixture("music-rename-help");
    for argument in ["-h", "--help"] {
        let output = case.run(&[argument]);
        assert_eq!(exited(&output), 0, "{argument}");
        assert_eq!(stdout(&output), USAGE, "{argument}");
        assert_eq!(stderr(&output), "", "{argument}");
        assert_eq!(case.argv("albumdetails"), "", "{argument}");
    }
}

#[test]
fn no_arguments_and_spaces_only_are_noops() {
    let case = fixture("music-rename-empty");
    for arguments in [vec![], vec!["   "], vec![""]] {
        let output = case.run(&arguments);
        assert_eq!(exited(&output), 0, "{arguments:?}");
        assert_eq!(stdout(&output), "");
        assert_eq!(stderr(&output), "");
        assert_eq!(case.argv("albumdetails"), "", "{arguments:?}");
    }
}

#[test]
fn files_mode_renames_the_parent_directory() {
    let case = fixture("music-rename-files");
    let output = run_with_data(&case, &["f", &track(&case)], full());
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");

    let src = artist_dir(&case);
    let dst = destination(&case, "The·Artist-⟨2xQ⟩-The·Album");
    assert_eq!(
        case.argv("albumdetails"),
        expected_argv("albumdetails", &[&track(&case)])
    );
    assert_eq!(
        case.argv("realpath"),
        format!("realpath\nARG -m\nARG --\nARG {src}\nrealpath\nARG -m\nARG --\nARG {dst}\n")
    );
    assert_eq!(
        case.argv("mv"),
        expected_argv("mv", &["-i", "--", &src, &dst])
    );
    assert_eq!(case.argv("ren"), expected_argv("ren", &["-i", "--", &dst]));
    assert_eq!(case.argv("rmdir"), expected_argv("rmdir", &["--", &src]));
}

#[test]
fn directory_mode_collects_metadata_with_find() {
    let case = fixture("music-rename-directory");
    let output = case
        .command()
        .env("XDG_MUSIC_DIR", music_dir(&case))
        .env("FAKE_FIND_OUT", full())
        .args([artist_dir(&case)])
        .output()
        .expect("run music-rename");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("find"),
        expected_argv(
            "find",
            &[&artist_dir(&case), "-exec", "albumdetails", "{}", "+"]
        )
    );
    assert_eq!(case.argv("albumdetails"), "", "find supplies the data");
    assert_eq!(
        case.argv("mv"),
        expected_argv(
            "mv",
            &[
                "-i",
                "--",
                &artist_dir(&case),
                &destination(&case, "The·Artist-⟨2xQ⟩-The·Album"),
            ]
        )
    );
}

#[test]
fn files_mode_passes_every_path_to_one_albumdetails_call() {
    let case = fixture("music-rename-two-files");
    let second = case.path("case/other.flac");
    case.write(&second, "audio");
    let output = run_with_data(
        &case,
        &["f", &track(&case), &second.to_string_lossy()],
        full(),
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("albumdetails"),
        expected_argv("albumdetails", &[&track(&case), &second.to_string_lossy()])
    );
    assert_eq!(
        case.argv("mv"),
        expected_argv(
            "mv",
            &[
                "-i",
                "--",
                &artist_dir(&case),
                &destination(&case, "The·Artist-⟨2xQ⟩-The·Album"),
            ]
        )
    );
}

#[test]
fn the_year_table_matches_the_original_including_its_quirks() {
    for (year, expected) in [
        ("1800", "A-⟨1800⟩-B"),
        ("1889", "A-⟨1889⟩-B"),
        ("1890", "A-⟨180⟩-B"),
        ("1899", "A-⟨189⟩-B"),
        ("1900", "A-⟨1x00⟩-B"),
        ("1975", "A-⟨1x75⟩-B"),
        ("1989", "A-⟨1x89⟩-B"),
        ("1990", "A-⟨1x0⟩-B"),
        ("1995", "A-⟨1x5⟩-B"),
        ("1999", "A-⟨1x9⟩-B"),
        ("2000", "A-⟨2x0⟩-B"),
        ("2001", "A-⟨2x1⟩-B"),
        ("2009", "A-⟨2x9⟩-B"),
        ("2010", "A-⟨2xA⟩-B"),
        ("2026", "A-⟨2xQ⟩-B"),
        ("2035", "A-⟨2xZ⟩-B"),
    ] {
        let case = fixture("music-rename-year");
        let data = format!("Artist: A\nYear: {year}\nAlbum: B");
        let output = run_with_data(&case, &["f", &track(&case)], &data);
        assert_eq!(exited(&output), 0, "{year}");
        assert_eq!(
            case.argv("mv"),
            expected_argv(
                "mv",
                &[
                    "-i",
                    "--",
                    &artist_dir(&case),
                    &destination(&case, expected),
                ]
            ),
            "year {year}"
        );
    }
}

#[test]
fn unknown_years_and_missing_fields_skip_the_rename() {
    for data in [
        "Artist: A\nYear: 2036\nAlbum: B",
        "Artist: A\nYear: 1700\nAlbum: B",
        "Artist: A\nAlbum: B",
        "Artist: A\nYear: 2026",
        "Year: 2026\nAlbum: B",
        "Artist:\nYear: 2026\nAlbum: B",
    ] {
        let case = fixture("music-rename-skip");
        let output = run_with_data(&case, &["f", &track(&case)], data);
        assert_eq!(exited(&output), 0, "{data:?}");
        assert_eq!(case.argv("mv"), "", "{data:?}");
        assert_eq!(case.argv("ren"), "", "{data:?}");
    }
}

#[test]
fn slashes_become_dashes_and_spaces_become_middle_dots() {
    let case = fixture("music-rename-characters");
    let output = run_with_data(
        &case,
        &["f", &track(&case)],
        "Artist:  A / B  \nYear:  2026 x\nAlbum:  Al/bum One  ",
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("mv"),
        expected_argv(
            "mv",
            &[
                "-i",
                "--",
                &artist_dir(&case),
                &destination(&case, "A·-·B-⟨2xQ⟩-Al-bum·One"),
            ]
        )
    );
}

#[test]
fn an_unset_music_dir_puts_the_result_at_the_root() {
    let case = fixture("music-rename-no-music-dir");
    let output = case
        .command()
        .env("XDG_MUSIC_DIR", "")
        .env("FAKE_ALBUMDETAILS_OUT", full())
        .args(["f", &track(&case)])
        .output()
        .expect("run music-rename");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("mv"),
        expected_argv(
            "mv",
            &[
                "-i",
                "--",
                &artist_dir(&case),
                "/The·Artist-⟨2xQ⟩-The·Album",
            ]
        ),
        "a dry-run target at / is safe with the fake mv"
    );
}

#[test]
fn current_mode_asks_mpd_and_renames_that_directory() {
    let case = fixture("music-rename-current");
    fs::create_dir_all(case.path("music-ren/ArtistDir")).expect("create current album dir");
    let output = case
        .command()
        .env("XDG_MUSIC_DIR", music_dir(&case))
        .env("FAKE_FIND_OUT", full())
        .env("FAKE_NC_OUT", "file: ArtistDir/track.flac\nOK\n")
        .args(["current"])
        .output()
        .expect("run music-rename");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("nc"),
        expected_argv("nc", &["-w", "1", "localhost", "6600"])
    );
    assert_eq!(
        case.stdin("nc"),
        "currentsong\nclose\n\n",
        "print adds the newline after the payload"
    );
    assert_eq!(
        case.argv("find"),
        expected_argv(
            "find",
            &[
                &format!("{}/ArtistDir", music_dir(&case)),
                "-exec",
                "albumdetails",
                "{}",
                "+",
            ]
        )
    );
    assert_eq!(
        case.argv("mv"),
        expected_argv(
            "mv",
            &[
                "-i",
                "--",
                &format!("{}/ArtistDir", music_dir(&case)),
                &destination(&case, "The·Artist-⟨2xQ⟩-The·Album"),
            ]
        )
    );
}

#[test]
fn mpd_host_can_carry_a_password_and_the_port_is_configurable() {
    let case = fixture("music-rename-mpd-password");
    fs::create_dir_all(case.path("music-ren/ArtistDir")).expect("create current album dir");
    let output = case
        .command()
        .env("XDG_MUSIC_DIR", music_dir(&case))
        .env("MPD_HOST", "pw@localhost")
        .env("MPD_PORT", "6611")
        .env("FAKE_NC_OUT", "file: ArtistDir/track.flac\n")
        .args(["c"])
        .output()
        .expect("run music-rename");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("nc"),
        expected_argv("nc", &["-w", "1", "localhost", "6611"])
    );
    assert_eq!(case.stdin("nc"), "password pw\ncurrentsong\nclose\n\n");
}

#[test]
fn socat_is_used_when_nc_is_missing() {
    let case = fixture("music-rename-socat");
    case.remove_fake("nc");
    fs::create_dir_all(case.path("music-ren/ArtistDir")).expect("create current album dir");
    let output = case
        .command()
        .env("XDG_MUSIC_DIR", music_dir(&case))
        .env("FAKE_SOCAT_OUT", "file: ArtistDir/track.flac\n")
        .env("FAKE_FIND_OUT", full())
        .args(["current"])
        .output()
        .expect("run music-rename");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("socat"),
        expected_argv("socat", &["-", "TCP:localhost:6600,connect-timeout=1"])
    );
    assert_eq!(case.stdin("socat"), "currentsong\nclose\n\n");
    assert_eq!(
        case.argv("mv"),
        expected_argv(
            "mv",
            &[
                "-i",
                "--",
                &format!("{}/ArtistDir", music_dir(&case)),
                &destination(&case, "The·Artist-⟨2xQ⟩-The·Album"),
            ]
        )
    );
}

#[test]
fn no_track_or_no_mpd_client_is_a_hard_error() {
    let case = fixture("music-rename-no-track");
    let output = case
        .command()
        .env("XDG_MUSIC_DIR", music_dir(&case))
        .env("FAKE_NC_OUT", "")
        .args(["current"])
        .output()
        .expect("run music-rename");
    assert_eq!(exited(&output), 1);
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "No current track from MPD\n");

    let case = fixture("music-rename-no-mpd-client");
    case.remove_fake("nc");
    case.remove_fake("socat");
    let output = case
        .command()
        .env("XDG_MUSIC_DIR", music_dir(&case))
        .args(["current"])
        .output()
        .expect("run music-rename");
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        "Neither nc nor socat found\nNo current track from MPD\n"
    );
}

#[test]
fn a_missing_albumdetails_keeps_the_rename_a_noop() {
    let case = fixture("music-rename-no-albumdetails");
    case.remove_fake("albumdetails");
    let output = run_with_data(&case, &["f", &track(&case)], "");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stderr(&output),
        "rename_files:1: command not found: albumdetails\n"
    );
    assert_eq!(case.argv("realpath"), "");
    assert_eq!(case.argv("mv"), "");
}

#[test]
fn mv_and_ren_failures_do_not_stop_the_following_steps() {
    let case = fixture("music-rename-failures");
    let output = case
        .command()
        .env("XDG_MUSIC_DIR", music_dir(&case))
        .env("FAKE_ALBUMDETAILS_OUT", full())
        .env("FAKE_MV_CODE", "1")
        .env("FAKE_REN_CODE", "1")
        .args(["f", &track(&case)])
        .output()
        .expect("run music-rename");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("mv"),
        expected_argv(
            "mv",
            &[
                "-i",
                "--",
                &artist_dir(&case),
                &destination(&case, "The·Artist-⟨2xQ⟩-The·Album"),
            ]
        )
    );
    assert_eq!(
        case.argv("ren"),
        expected_argv(
            "ren",
            &[
                "-i",
                "--",
                &destination(&case, "The·Artist-⟨2xQ⟩-The·Album")
            ]
        )
    );
    assert_eq!(
        case.argv("rmdir"),
        expected_argv("rmdir", &["--", &artist_dir(&case)])
    );
}

#[test]
fn a_missing_realpath_compares_equal_and_skips_mv() {
    let case = fixture("music-rename-no-realpath");
    case.remove_fake("realpath");
    let output = run_with_data(&case, &["f", &track(&case)], full());
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stderr(&output),
        "rename:27: command not found: realpath\n\
         rename:27: command not found: realpath\n"
    );
    assert_eq!(case.argv("mv"), "");
    assert_eq!(
        case.argv("ren"),
        expected_argv(
            "ren",
            &[
                "-i",
                "--",
                &destination(&case, "The·Artist-⟨2xQ⟩-The·Album")
            ]
        )
    );
}

#[test]
fn running_on_the_already_renamed_directory_skips_mv() {
    let case = fixture("music-rename-idempotent");
    let name = "The·Artist-⟨2xQ⟩-The·Album";
    let renamed = case.path(&format!("music-ren/{name}"));
    fs::create_dir_all(&renamed).expect("create renamed directory");
    let output = case
        .command()
        .env("XDG_MUSIC_DIR", music_dir(&case))
        .env("FAKE_FIND_OUT", full())
        .arg(&renamed)
        .output()
        .expect("run music-rename");
    assert_eq!(exited(&output), 0);
    assert_eq!(case.argv("mv"), "", "src and result are the same path");
    assert_eq!(
        case.argv("ren"),
        expected_argv("ren", &["-i", "--", &renamed.to_string_lossy()])
    );
    assert_eq!(
        case.argv("rmdir"),
        expected_argv("rmdir", &["--", &renamed.to_string_lossy()])
    );
}

#[test]
fn empty_metadata_skips_everything_after_albumdetails() {
    let case = fixture("music-rename-empty-metadata");
    let output = run_with_data(&case, &["f", &track(&case)], "");
    assert_eq!(exited(&output), 0);
    assert_eq!(case.argv("realpath"), "");
    assert_eq!(case.argv("mv"), "");
    assert_eq!(case.argv("ren"), "");
}
