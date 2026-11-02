//! Hermetic tests for the `music-highlevel` port.
//!
//! A fake `streaming_extractor_music` receives the two expected argv elements
//! and writes `$FAKE_JSON_CONTENT` (one of the fixtures in `tests/parity/`) to
//! the output path; a fake `playerctl` answers the current-track query. The
//! fixtures are shared with `tests/parity.sh`, which compares the same cases
//! against the Python original.

mod support;

use support::{exited, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_music-highlevel");
const HIGHLEVEL: &str = include_str!("parity/highlevel.json");
const EDGE: &str = include_str!("parity/edge.json");

const EXTRACTOR: &str = r#"#!/bin/sh
printf 'extractor\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
printf 'extractor-stdout-noise\n'
printf 'extractor-stderr-noise\n' >&2
case "$1" in
  *fail.mp3) exit 3 ;;
  *nofile.mp3) exit 0 ;;
esac
if [ -n "${FAKE_JSON_CONTENT+set}" ]; then
  printf '%s' "$FAKE_JSON_CONTENT" > "$2"
fi
exit 0
"#;

const PLAYERCTL: &str = r#"#!/bin/sh
printf 'playerctl\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
printf '%s' "${FAKE_TRACK:-}"
exit "${FAKE_TRACK_CODE:-0}"
"#;

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("streaming_extractor_music", EXTRACTOR);
    case.write_fake("playerctl", PLAYERCTL);
    std::fs::create_dir_all(case.path("media")).expect("create media directory");
    case
}

fn audio(case: &Case, name: &str) -> std::path::PathBuf {
    let path = case.path("media").join(name);
    case.write(&path, "");
    path
}

fn extractor_calls(case: &Case) -> Vec<(String, String)> {
    let log = case.argv_log();
    let mut calls = Vec::new();
    let mut lines = log.lines().peekable();
    while let Some(line) = lines.next() {
        if line == "extractor" {
            let source = lines.next().unwrap_or_default().trim().to_string();
            let output = lines.next().unwrap_or_default().trim().to_string();
            calls.push((source, output));
        }
    }
    calls
}

#[test]
fn help_is_the_python_argparse_text() {
    let case = fixture("help");
    let output = case.run(&["--help"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stderr(&output), "");
    assert_eq!(
        stdout(&output),
        "\
usage: music-highlevel [-h] [--top TOP] [--taxonomies [TAXONOMIES ...]]
                       [--json]
                       [paths ...]

Inspect Essentia highlevel classifiers for audio files

positional arguments:
  paths                 audio files or directories; defaults to current track
                        via playerctl

options:
  -h, --help            show this help message and exit
  --top TOP             top probabilities per taxonomy to display
  --taxonomies [TAXONOMIES ...]
                        specific highlevel taxonomies to include (defaults to
                        a common subset)
  --json                emit JSON per track
"
    );
}

#[test]
fn json_output_matches_orjson() {
    let case = fixture("json-output");
    let track = audio(&case, "a.mp3");
    let output = case
        .command()
        .env("FAKE_JSON_CONTENT", HIGHLEVEL)
        .args(["--json", track.to_str().expect("UTF-8 path")])
        .output()
        .expect("run music-highlevel");
    assert_eq!(exited(&output), 0);
    assert_eq!(stderr(&output), "");
    assert_eq!(
        stdout(&output),
        format!(
            concat!(
                "{{\"path\":\"{path}\",\"highlevel\":{{",
                "\"genre_dortmund\":{{\"candidates\":[",
                "{{\"label\":\"rock\",\"score\":0.5}},",
                "{{\"label\":\"pop\",\"score\":0.25}},",
                "{{\"label\":\"jazz\",\"score\":0.25}}],\"value\":\"rock\"}},",
                "\"danceability\":{{\"score\":0.75,\"value\":1.0}},",
                "\"moods_mirex\":{{\"candidates\":[",
                "{{\"label\":\"happy\",\"score\":0.9}},",
                "{{\"label\":\"sad\",\"score\":0.1}}],\"value\":\"happy\"}},",
                "\"tonal_atonal\":{{\"candidates\":[",
                "{{\"label\":\"atonal\",\"score\":0.125}}],\"value\":0.5}}}}}}\n"
            ),
            path = track.display()
        )
    );
    let calls = extractor_calls(&case);
    assert_eq!(calls.len(), 1);
    assert_eq!(calls[0].0, track.display().to_string());
    assert!(
        calls[0].1.starts_with(&format!("{}/", case.tmp.display())),
        "output must be inside TMPDIR: {}",
        calls[0].1
    );
    assert!(calls[0].1.ends_with("/highlevel.json"));
    // TemporaryDirectory is removed after the track; nothing may leak.
    assert_eq!(std::fs::read_dir(&case.tmp).expect("read tmp").count(), 0);
}

#[test]
fn human_output_lists_candidates_sorted() {
    let case = fixture("human-output");
    let track = audio(&case, "a.mp3");
    let output = case
        .command()
        .env("FAKE_JSON_CONTENT", HIGHLEVEL)
        .arg(track.to_str().expect("UTF-8 path"))
        .output()
        .expect("run music-highlevel");
    assert_eq!(exited(&output), 0);
    assert_eq!(stderr(&output), "");
    assert_eq!(
        stdout(&output),
        format!(
            "{path}\n\
             \x20 genre_dortmund: value=rock\n\
             \x20   0.500\trock\n\
             \x20   0.250\tpop\n\
             \x20   0.250\tjazz\n\
             \x20 danceability: value=1.0 score=0.750\n\
             \x20 moods_mirex: value=happy\n\
             \x20   0.900\thappy\n\
             \x20   0.100\tsad\n\
             \x20 tonal_atonal: value=0.5\n\
             \x20   0.125\tatonal\n",
            path = track.display()
        )
    );
}

#[test]
fn edge_values_follow_python_semantics() {
    let case = fixture("edge-values");
    let track = audio(&case, "a.mp3");
    let output = case
        .command()
        .env("FAKE_JSON_CONTENT", EDGE)
        .args(["--json", track.to_str().expect("UTF-8 path")])
        .output()
        .expect("run music-highlevel");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        format!(
            concat!(
                "{{\"path\":\"{path}\",\"highlevel\":{{",
                "\"genre_dortmund\":{{\"value\":\"a\"}},",
                "\"danceability\":{{\"score\":2.0,\"value\":0.0}},",
                "\"moods_mirex\":{{\"candidates\":[{{\"label\":\"x\",\"score\":0.5}}]}},",
                "\"tonal_atonal\":{{\"candidates\":[{{\"label\":\"y\",\"score\":0.5}}]}}}}}}\n"
            ),
            path = track.display()
        )
    );
}

#[test]
fn top_and_taxonomies_filter_the_projection() {
    let case = fixture("selection");
    let track = audio(&case, "a.mp3");
    // The track has to precede `--taxonomies`: its nargs='*' would otherwise
    // swallow the path as another taxonomy name.
    let arguments = [
        "--json",
        "--top",
        "2",
        track.to_str().expect("UTF-8 path"),
        "--taxonomies",
        "genre_dortmund",
        "tonal_atonal",
    ];
    let output = case
        .command()
        .env("FAKE_JSON_CONTENT", HIGHLEVEL)
        .args(arguments)
        .output()
        .expect("run music-highlevel");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        format!(
            concat!(
                "{{\"path\":\"{path}\",\"highlevel\":{{",
                "\"genre_dortmund\":{{\"candidates\":[",
                "{{\"label\":\"rock\",\"score\":0.5}},",
                "{{\"label\":\"pop\",\"score\":0.25}}],\"value\":\"rock\"}},",
                "\"tonal_atonal\":{{\"candidates\":[",
                "{{\"label\":\"atonal\",\"score\":0.125}}],\"value\":0.5}}}}}}\n"
            ),
            path = track.display()
        )
    );
}

#[test]
fn directories_are_walked_in_sorted_order() {
    let case = fixture("walk");
    let first = audio(&case, "b.ogg");
    let spaced = audio(&case, "a space.mp3");
    let upper = audio(&case, "C.FLAC");
    let ignored = audio(&case, "notes.txt");
    let nested = audio(&case, "sub/d.wav");
    assert!(ignored.exists());
    let output = case
        .command()
        .env("FAKE_JSON_CONTENT", HIGHLEVEL)
        .args(["--json", case.path("media").to_str().expect("UTF-8 path")])
        .output()
        .expect("run music-highlevel");
    assert_eq!(exited(&output), 0);
    let sources: Vec<String> = extractor_calls(&case)
        .into_iter()
        .map(|call| call.0)
        .collect();
    assert_eq!(
        sources,
        vec![
            upper.display().to_string(),
            spaced.display().to_string(),
            first.display().to_string(),
            nested.display().to_string(),
        ]
    );
}

#[test]
fn explicit_files_are_accepted_regardless_of_extension() {
    let case = fixture("explicit-file");
    let track = audio(&case, "notes.txt");
    let output = case
        .command()
        .env("FAKE_JSON_CONTENT", HIGHLEVEL)
        .args(["--json", track.to_str().expect("UTF-8 path")])
        .output()
        .expect("run music-highlevel");
    assert_eq!(exited(&output), 0);
    assert_eq!(extractor_calls(&case).len(), 1);
}

#[test]
fn extractor_stdout_and_stderr_are_discarded() {
    let case = fixture("extractor-noise");
    let track = audio(&case, "a.mp3");
    let output = case
        .command()
        .env("FAKE_JSON_CONTENT", HIGHLEVEL)
        .args(["--json", track.to_str().expect("UTF-8 path")])
        .output()
        .expect("run music-highlevel");
    assert_eq!(exited(&output), 0);
    assert!(!stdout(&output).contains("extractor-stdout-noise"));
    assert!(!stderr(&output).contains("extractor-stderr-noise"));
}

#[test]
fn missing_highlevel_section_is_reported_and_skipped() {
    let case = fixture("missing-highlevel");
    let track = audio(&case, "a.mp3");
    let output = case
        .command()
        .env("FAKE_JSON_CONTENT", "{}")
        .args(["--json", track.to_str().expect("UTF-8 path")])
        .output()
        .expect("run music-highlevel");
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        format!(
            "[music-highlevel] missing highlevel section: {}\n",
            track.display()
        )
    );
}

#[test]
fn empty_highlevel_section_is_reported_in_both_formats() {
    let case = fixture("empty-highlevel");
    let track = audio(&case, "a.mp3");
    let output = case
        .command()
        .env("FAKE_JSON_CONTENT", "{\"highlevel\":{}}")
        .arg(track.to_str().expect("UTF-8 path"))
        .output()
        .expect("run music-highlevel");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        format!("{}\n  (no highlevel data)\n", track.display())
    );

    let output = case
        .command()
        .env("FAKE_JSON_CONTENT", "{\"highlevel\":{}}")
        .args(["--json", track.to_str().expect("UTF-8 path")])
        .output()
        .expect("run music-highlevel");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        format!("{{\"path\":\"{}\",\"highlevel\":{{}}}}\n", track.display())
    );
}

#[test]
fn malformed_output_reports_the_orjson_error() {
    let case = fixture("malformed");
    let track = audio(&case, "a.mp3");
    let output = case
        .command()
        .env("FAKE_JSON_CONTENT", "not json")
        .args(["--json", track.to_str().expect("UTF-8 path")])
        .output()
        .expect("run music-highlevel");
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        format!(
            "[music-highlevel] failed reading output for {}: \
             invalid literal, expected 'null': line 1 column 1 (char 0)\n",
            track.display()
        )
    );
}

#[test]
fn extractor_failure_reports_and_continues_with_the_next_track() {
    let case = fixture("extractor-failure");
    let failing = audio(&case, "fail.mp3");
    let good = audio(&case, "b.mp3");
    let output = case
        .command()
        .env("FAKE_JSON_CONTENT", HIGHLEVEL)
        .args([
            "--json",
            failing.to_str().expect("UTF-8 path"),
            good.to_str().expect("UTF-8 path"),
        ])
        .output()
        .expect("run music-highlevel");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stderr(&output),
        format!(
            "[music-highlevel] extractor failed: {}\n",
            failing.display()
        )
    );
    assert!(stdout(&output).contains(&format!("\"path\":\"{}\"", good.display())));
}

#[test]
fn missing_output_file_reports_a_python_style_os_error() {
    let case = fixture("no-output");
    let track = audio(&case, "nofile.mp3");
    let output = case
        .command()
        .args(["--json", track.to_str().expect("UTF-8 path")])
        .output()
        .expect("run music-highlevel");
    assert_eq!(exited(&output), 0);
    let message = stderr(&output);
    assert!(
        message.starts_with(&format!(
            "[music-highlevel] failed reading output for {}: [Errno 2] No such file or directory: '",
            track.display()
        )),
        "stderr: {message}"
    );
    assert!(message.ends_with("/highlevel.json'\n"), "stderr: {message}");
}

#[test]
fn playerctl_fallback_uses_the_file_url() {
    let case = fixture("playerctl");
    let track = audio(&case, "a b.mp3");
    let encoded = track.display().to_string().replace(' ', "%20");
    let output = case
        .command()
        .env("FAKE_JSON_CONTENT", HIGHLEVEL)
        .env("FAKE_TRACK", format!("file://{encoded}"))
        .args(["--json"])
        .output()
        .expect("run music-highlevel");
    assert_eq!(exited(&output), 0);
    assert!(stdout(&output).contains(&format!("\"path\":\"{}\"", track.display())));
    assert!(case
        .argv_log()
        .contains("playerctl\n  metadata\n  xesam:url\n"));
}

#[test]
fn no_inputs_and_no_audio_files_are_errors() {
    let case = fixture("no-inputs");
    let output = case
        .command()
        .env("FAKE_TRACK", "")
        .output()
        .expect("run music-highlevel");
    assert_eq!(exited(&output), 1);
    assert_eq!(stderr(&output), "[music-highlevel] no inputs provided\n");

    let output = case.run(&["/definitely/not/here"]);
    assert_eq!(exited(&output), 1);
    assert_eq!(stderr(&output), "[music-highlevel] no audio files found\n");
}

#[test]
fn missing_extractor_aborts_with_status_one() {
    let case = fixture("no-extractor");
    let track = audio(&case, "a.mp3");
    case.remove_fake("streaming_extractor_music");
    let output = case
        .command()
        .args(["--json", track.to_str().expect("UTF-8 path")])
        .output()
        .expect("run music-highlevel");
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        "[music-highlevel] cannot run streaming_extractor_music: No such file or directory\n"
    );
}

#[test]
fn non_object_extractor_output_aborts() {
    let case = fixture("non-object");
    let track = audio(&case, "a.mp3");
    let output = case
        .command()
        .env("FAKE_JSON_CONTENT", "[]")
        .args(["--json", track.to_str().expect("UTF-8 path")])
        .output()
        .expect("run music-highlevel");
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        format!(
            "[music-highlevel] extractor output is not a JSON object: {}\n",
            track.display()
        )
    );
}

#[test]
fn argument_errors_print_usage_and_exit_two() {
    let case = fixture("usage-error");
    let output = case.run(&["--bogus"]);
    assert_eq!(exited(&output), 2);
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        "usage: music-highlevel [-h] [--top TOP] [--taxonomies [TAXONOMIES ...]]
                       [--json]
                       [paths ...]
music-highlevel: error: unrecognized arguments: --bogus
"
    );

    let output = case.run(&["--top", "x"]);
    assert_eq!(exited(&output), 2);
    assert!(stderr(&output)
        .ends_with("music-highlevel: error: argument --top: invalid int value: 'x'\n"));

    let output = case.run(&["--t=3"]);
    assert_eq!(exited(&output), 2);
    assert!(stderr(&output).ends_with(
        "music-highlevel: error: ambiguous option: --t=3 could match --top, --taxonomies\n"
    ));
}

#[test]
fn columns_controls_the_help_width() {
    let case = fixture("columns");
    let output = case
        .command()
        .env("COLUMNS", "40")
        .arg("--help")
        .output()
        .expect("run music-highlevel");
    assert_eq!(exited(&output), 0);
    assert!(stdout(&output).starts_with("usage: music-highlevel [-h]\n"));
    assert!(stdout(&output).contains("Inspect Essentia highlevel classifiers\nfor audio files\n"));
}
