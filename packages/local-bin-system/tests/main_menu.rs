//! Hermetic tests for the `main-menu` port: the menu list, both non-dmenu
//! entry points, every action's external argv and clipboard payload, and the
//! dmenu handler (including the shell's "last line without newline is not
//! read" behaviour).

mod support;

use support::{exited, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_main-menu");

const LOG_ARGS: &str = r#"#!/bin/sh
printf 'cmd %s\n' "${0##*/}" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
"#;

const RMPC: &str = r#"#!/bin/sh
printf 'cmd rmpc\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
printf '%s' "${FAKE_SONG:-}"
"#;

const WL_COPY: &str = r#"#!/bin/sh
printf 'cmd wl-copy\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
while IFS= read -r -N 1 character; do printf '%s' "$character" >> "$FAKE_CLIP"; done
"#;

const WL_PASTE: &str = r#"#!/bin/sh
printf 'cmd wl-paste\n' >> "$FAKE_ARGV_LOG"
printf '%s' "${FAKE_PASTE:-}"
"#;

const TRANS: &str = r#"#!/bin/sh
printf 'cmd trans\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
printf '%s' "${FAKE_TRANS:-}"
"#;

const NC: &str = r#"#!/bin/sh
printf 'cmd nc\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
while IFS= read -r -N 1 character; do :; done
printf '%s\n' "${FAKE_NC:-termbin.invalid/xyz}"
"#;

const VICINAE: &str = r#"#!/bin/sh
printf 'cmd vicinae\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
while IFS= read -r line; do printf '  in %s\n' "$line" >> "$FAKE_ARGV_LOG"; done
printf '%s' "${FAKE_SEL:-}"
"#;

const SONG: &str = r#"{"metadata":{"artist":"Artist","title":"Title","album":"Album","name":"Name"},"file":"a/b.mp3"}"#;

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("rmpc", RMPC);
    case.write_fake("wl-copy", WL_COPY);
    case.write_fake("wl-paste", WL_PASTE);
    case.write_fake("trans", TRANS);
    case.write_fake("nc", NC);
    case.write_fake("notify-send", LOG_ARGS);
    case.write_fake("play-sound", LOG_ARGS);
    case.write_fake("vicinae", VICINAE);
    for helper in [
        "rmpc-pause",
        "rmpc-play",
        "rmpc-enableoutput",
        "rmpc-disableoutput",
        "sleep",
    ] {
        case.write_fake(helper, LOG_ARGS);
    }
    case
}

fn song_env(song: &str) -> Vec<(&str, &str)> {
    vec![("FAKE_SONG", song)]
}

#[test]
fn list_prints_the_actions_in_order() {
    let case = fixture("list");
    let output = case.run(&["--list"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        "title_copy\nartist_copy\nalbum_copy\npath_copy\npipewire_output\nalsa_output\ntranslate\ntermbin\n"
    );
    assert_eq!(stderr(&output), "");
}

#[test]
fn help_is_one_line() {
    let case = fixture("help");
    for argument in ["--help", "-h"] {
        let output = case.run(&[argument]);
        assert_eq!(exited(&output), 0);
        assert_eq!(stdout(&output), "usage: main-menu [--list | --run NAME]\n");
    }
}

#[test]
fn run_needs_and_validates_an_action_name() {
    let case = fixture("run-errors");
    let missing = case.run(&["--run"]);
    assert_eq!(exited(&missing), 2);
    assert_eq!(stderr(&missing), "main-menu: --run needs an action name\n");

    let empty = case.run(&["--run", ""]);
    assert_eq!(exited(&empty), 2);
    assert_eq!(stderr(&empty), "main-menu: --run needs an action name\n");

    let unknown = case.run(&["--run", "nope"]);
    assert_eq!(exited(&unknown), 2);
    assert_eq!(stderr(&unknown), "main-menu: unknown action: nope\n");
    assert_eq!(case.argv_log(), "");
}

#[test]
fn title_copy_joins_artist_and_title() {
    let case = fixture("title");
    let output = case.run_env(&["--run", "title_copy"], &song_env(SONG));
    assert_eq!(exited(&output), 0);
    assert_eq!(case.clip_log(), "Artist - Title\n");
    assert!(case.argv_log().contains("cmd rmpc\n  song\n"));
}

#[test]
fn title_copy_falls_back_to_title_then_name_then_empty() {
    let title_only = fixture("title-only");
    let _ = title_only.run_env(
        &["--run", "title_copy"],
        &song_env(r#"{"metadata":{"title":"Only"}}"#),
    );
    assert_eq!(title_only.clip_log(), "Only\n");

    let name_only = fixture("name-only");
    let _ = name_only.run_env(
        &["--run", "title_copy"],
        &song_env(r#"{"metadata":{"name":"Named"}}"#),
    );
    assert_eq!(name_only.clip_log(), "Named\n");

    let empty = fixture("empty-song");
    let _ = empty.run_env(&["--run", "title_copy"], &song_env("{}"));
    assert_eq!(empty.clip_log(), "\n");

    let malformed = fixture("malformed-song");
    let _ = malformed.run_env(&["--run", "title_copy"], &song_env("not json"));
    assert_eq!(malformed.clip_log(), "");
}

#[test]
fn empty_string_metadata_is_truthy_like_jq() {
    let case = fixture("empty-strings");
    let _ = case.run_env(
        &["--run", "title_copy"],
        &song_env(r#"{"metadata":{"artist":"","title":""}}"#),
    );
    assert_eq!(case.clip_log(), " - \n");
}

#[test]
fn artist_and_album_copy_use_jq_alt_empty() {
    let artist = fixture("artist");
    let _ = artist.run_env(&["--run", "artist_copy"], &song_env(SONG));
    assert_eq!(artist.clip_log(), "Artist\n");

    let album = fixture("album");
    let _ = album.run_env(&["--run", "album_copy"], &song_env(SONG));
    assert_eq!(album.clip_log(), "Album\n");

    let missing = fixture("album-missing");
    let _ = missing.run_env(&["--run", "album_copy"], &song_env("{}"));
    // jq's `// empty` emits zero bytes; the clipboard is still invoked.
    assert_eq!(missing.clip_log(), "");
    assert!(missing.argv_log().contains("cmd wl-copy\n"));
}

#[test]
fn path_copy_prefixes_the_music_directory() {
    let case = fixture("path");
    let _ = case.run_env(
        &["--run", "path_copy"],
        &[("FAKE_SONG", SONG), ("XDG_MUSIC_DIR", "/music")],
    );
    assert_eq!(case.clip_log(), "/music/a/b.mp3\n");

    let empty = fixture("path-empty");
    let _ = empty.run_env(&["--run", "path_copy"], &song_env(r#"{"file":""}"#));
    assert_eq!(empty.clip_log(), "");
    assert!(!empty.argv_log().contains("cmd wl-copy"));
}

#[test]
fn pipewire_output_switches_the_outputs() {
    let case = fixture("pipewire");
    let output = case.run(&["--run", "pipewire_output"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv_log(),
        "cmd rmpc-pause\ncmd rmpc-enableoutput\n  PipeWire\ncmd rmpc-disableoutput\n  RME HDSPe AIO\ncmd rmpc-play\n"
    );
}

#[test]
fn alsa_output_switches_back_and_waits() {
    let case = fixture("alsa");
    let output = case.run(&["--run", "alsa_output"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv_log(),
        "cmd rmpc-pause\ncmd rmpc-enableoutput\n  RME HDSPe AIO\ncmd rmpc-disableoutput\n  PipeWire\ncmd rmpc-play\ncmd sleep\n  5s\ncmd rmpc-play\n"
    );
}

#[test]
fn translate_pastes_translates_and_notifies() {
    let case = fixture("translate");
    let output = case.run_env(
        &["--run", "translate"],
        &[("FAKE_PASTE", "hello"), ("FAKE_TRANS", "privet")],
    );
    assert_eq!(exited(&output), 0);
    let argv = case.argv_log();
    assert!(argv.contains("cmd wl-paste\n"), "{argv}");
    assert!(
        argv.contains("cmd trans\n  -brief\n  :ru\n  hello\n"),
        "{argv}"
    );
    assert!(
        argv.contains("cmd notify-send\n  -t\n  750\n  privet\n"),
        "{argv}"
    );
    assert!(argv.contains("cmd play-sound\n  cyclist.ogg\n"), "{argv}");
}

#[test]
fn termbin_publishes_and_copies_the_url() {
    let case = fixture("termbin");
    let output = case.run_env(
        &["--run", "termbin"],
        &[
            ("FAKE_PASTE", "payload"),
            ("FAKE_NC", "termbin.invalid/abc"),
        ],
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(case.clip_log(), "termbin.invalid/abc\n");
    let argv = case.argv_log();
    assert!(argv.contains("cmd nc\n  termbin.com\n  9999\n"), "{argv}");
    assert!(
        argv.contains("cmd notify-send\n  termbin.invalid/abc copied to clipboard\n"),
        "{argv}"
    );
    assert!(argv.contains("cmd play-sound\n  direct.ogg\n"), "{argv}");
}

#[test]
fn dmenu_runs_every_terminated_selection() {
    let case = fixture("dmenu");
    let output = case.run_env(
        &[],
        &[
            ("FAKE_SEL", "translate\nalbum_copy\n"),
            ("FAKE_PASTE", "hello"),
            ("FAKE_TRANS", "privet"),
            ("FAKE_SONG", SONG),
        ],
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(case.clip_log(), "Album\n");
    let argv = case.argv_log();
    assert!(
        argv.contains("cmd vicinae\n  dmenu\n  -p\n  ❯>\n"),
        "{argv}"
    );
    assert!(argv.contains("  in translate\n"), "{argv}");
    assert!(argv.contains("  in album_copy\n"), "{argv}");
    assert!(argv.contains("cmd play-sound\n  cyclist.ogg\n"), "{argv}");
}

#[test]
fn dmenu_skips_an_unterminated_final_line_like_the_shell_read_loop() {
    let case = fixture("dmenu-unterminated");
    let output = case.run_env(&[], &[("FAKE_SEL", "title_copy"), ("FAKE_SONG", SONG)]);
    assert_eq!(exited(&output), 0);
    // `while read` does not run its body for the unterminated last line.
    assert_eq!(case.clip_log(), "");
    assert!(!case.argv_log().contains("cmd rmpc"));
}

#[test]
fn dmenu_ignores_unknown_and_empty_lines() {
    let case = fixture("dmenu-unknown");
    let _ = case.run_env(
        &[],
        &[
            ("FAKE_SEL", "\nnot_an_action\n\ntitle_copy\n"),
            ("FAKE_SONG", SONG),
        ],
    );
    assert_eq!(case.clip_log(), "Artist - Title\n");
}

#[test]
fn dmenu_exits_zero_without_vicinae() {
    let case = fixture("no-vicinae");
    case.remove_fake("vicinae");
    let output = case.run(&[]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "");
}

#[test]
fn an_unknown_first_argument_falls_through_to_dmenu() {
    let case = fixture("unknown-arg");
    let output = case.run_env(
        &["--bogus"],
        &[("FAKE_SEL", "title_copy\n"), ("FAKE_SONG", SONG)],
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(case.clip_log(), "Artist - Title\n");
}
