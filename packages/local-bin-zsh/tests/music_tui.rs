//! Hermetic tests for the `music-tui` port.
//!
//! fd/fzf/mpv/playerctl/music-similar/music-highlevel/du/stat are fakes; the
//! music collection and the similarity index are fixtures under the per-case
//! tree, so the suite never reads the real ~/music or ~/.cache/music-index.

mod support;

use std::fs;

use support::{
    exited, expected_argv, fzf_script, playerctl_script, stderr, stdout, tool_script, Case,
};

const BIN: &str = env!("CARGO_BIN_EXE_music-tui");
const USAGE: &str = "\
music-tui: fzf-based TUI for music similarity, classification, and browsing
Usage: music-tui [similar|classify|profile|interactive]
  similar      Find similar tracks for current or selected track
  classify     Run highlevel classification on a selected file
  profile      Show music collection profile
  interactive  Browse music files with similarity previews
";

const PREVIEW_SIMILAR: &str =
    "p=\"$(echo {} | cut -f2-)\"; [ -n \"$p\" ] && music-highlevel \"$p\" 2>/dev/null | head -25";
const PREVIEW_MENU: &str = "\ncase {} in\n  similar)     echo \"Find similar tracks for current or selected track\";;\n  classify)    echo \"Run Essentia highlevel classification on a file\";;\n  profile)     echo \"Show collection statistics\";;\n  interactive) echo \"Browse music with similarity previews\";;\nesac";
const PREVIEW_BROWSE: &str = "\nf=\"{}\"\necho \"=== Similar tracks ===\"\nmusic-similar \"$f\" 2>/dev/null | head -8\necho \"\"\necho \"=== Highlevel ===\"\nmusic-highlevel \"$f\" 2>/dev/null | head -15\n";
const PREVIEW_DRILL: &str = "\np=\"$(echo {} | cut -f2-)\"\nif [ -n \"$p\" ] && [ -f \"$p\" ]; then\n  echo \"=== $p ===\"\n  music-highlevel \"$p\" 2>/dev/null | head -20\nfi\n";

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("fd", &support::fd_script());
    case.write_fake("fzf", &fzf_script());
    case.write_fake(
        "music-similar",
        &tool_script("music-similar", "MUSIC_SIMILAR"),
    );
    case.write_fake(
        "music-highlevel",
        &tool_script("music-highlevel", "MUSIC_HIGHLEVEL"),
    );
    case.write_fake("mpv", &tool_script("mpv", "MPV"));
    case.write_fake("playerctl", &playerctl_script());
    case.write_fake("du", &tool_script("du", "DU"));
    case.write_fake("stat", &tool_script("stat", "STAT"));
    fs::create_dir_all(case.path("music/a")).expect("create music tree");
    fs::create_dir_all(case.path("music/b")).expect("create music tree");
    case.write(&case.path("music/a/one.flac"), "x");
    case.write(&case.path("music/a/two.flac"), "x");
    case.write(&case.path("music/b/three.mp3"), "x");
    case
}

fn music_dir(case: &Case) -> String {
    case.path("music").to_string_lossy().into_owned()
}

fn one(case: &Case) -> String {
    case.path("music/a/one.flac").to_string_lossy().into_owned()
}

fn two(case: &Case) -> String {
    case.path("music/a/two.flac").to_string_lossy().into_owned()
}

fn index_dir(case: &Case) -> std::path::PathBuf {
    case.path("xdg/cache/music-index")
}

fn sequence(case: &Case, lines: &[&str]) {
    let mut content = String::new();
    for line in lines {
        content.push_str(line);
        content.push('\n');
    }
    case.write(&case.path("sequence"), &content);
}

fn run(case: &Case, arguments: &[&str]) -> std::process::Output {
    let mut command = case.command();
    command.env("MUSIC_DIR", music_dir(case));
    if case.path("sequence").exists() {
        command.env("FAKE_FZF_SEQ_FILE", case.path("sequence"));
    }
    command.args(arguments).output().expect("run music-tui")
}

fn fd_arguments(case: &Case, extra: &[&str]) -> String {
    let mut arguments = vec![
        "-t", "f", "-e", "mp3", "-e", "flac", "-e", "wav", "-e", "ogg", "-e", "m4a", "-e", "opus",
        "-e", "aac", "-e", "aiff", "-e", "wma", ".", "",
    ];
    let directory = music_dir(case);
    arguments[21] = &directory;
    arguments.extend_from_slice(extra);
    expected_argv("fd", &arguments)
}

#[test]
fn help_prints_the_header_without_running_tools() {
    let case = fixture("tui-help");
    for argument in ["-h", "--help"] {
        let output = run(&case, &[argument]);
        assert_eq!(exited(&output), 0, "{argument}");
        assert_eq!(stdout(&output), USAGE, "{argument}");
        assert_eq!(stderr(&output), "", "{argument}");
        assert_eq!(case.argv("fzf"), "", "{argument}");
    }
}

#[test]
fn unknown_modes_die_with_the_script_prefix() {
    let case = fixture("tui-unknown");
    let output = run(&case, &["bogus"]);
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        "music-tui: unknown mode: bogus (see -h for help)\n"
    );

    for alias in ["s", "c", "p", "stats", "i", "browse", "b"] {
        let case = fixture("tui-alias");
        let output = run(&case, &[alias]);
        assert_eq!(exited(&output), 0, "{alias}");
    }
}

#[test]
fn the_menu_prints_the_mode_list_and_handles_cancel() {
    let case = fixture("tui-menu");
    let output = run(&case, &[]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "");
    assert_eq!(
        case.argv("fzf"),
        expected_argv(
            "fzf",
            &[
                "--prompt=music-tui > ",
                "--header",
                "similar | classify | profile | interactive",
                "--preview",
                PREVIEW_MENU,
                "--preview-window=up:2",
            ]
        )
    );
    assert_eq!(
        case.read_at(&case.logs.join("fzf.stdin.1")),
        "similar\nclassify\nprofile\ninteractive\n"
    );
}

#[test]
fn a_bogus_menu_choice_reports_the_dynamic_call_diagnostic() {
    let case = fixture("tui-menu-bogus");
    sequence(&case, &["bogus"]);
    let output = run(&case, &[]);
    assert_eq!(exited(&output), 127);
    assert_eq!(
        stderr(&output),
        format!("{BIN}:230: command not found: mode_bogus\n")
    );
}

#[test]
fn similar_picks_a_track_and_plays_the_selection() {
    let case = fixture("tui-similar-pick");
    sequence(&case, &[&one(&case), &format!("0.9\t{}", two(&case))]);
    let output = case
        .command()
        .env("MUSIC_DIR", music_dir(&case))
        .env("FAKE_FZF_SEQ_FILE", case.path("sequence"))
        .env("FAKE_FD_OUT", format!("{}\n{}\n", one(&case), two(&case)))
        .env("FAKE_MUSIC_SIMILAR_OUT", format!("0.9\t{}", two(&case)))
        .env("FAKE_MPV_CODE", "4")
        .args(["similar"])
        .output()
        .expect("run music-tui similar");
    assert_eq!(exited(&output), 4);
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "Analyzing similarities for one.flac…\n");
    assert_eq!(case.argv("playerctl"), expected_argv("playerctl", &["-l"]));
    assert_eq!(case.argv("fd"), fd_arguments(&case, &[]));
    assert_eq!(
        case.argv("fzf"),
        format!(
            "{}{}",
            expected_argv(
                "fzf",
                &["--prompt=Pick track > ", "--header=No track playing"]
            ),
            expected_argv(
                "fzf",
                &[
                    "--prompt=Similar > ",
                    "--header",
                    "Enter=play | ESC=cancel",
                    "--preview",
                    PREVIEW_SIMILAR,
                    "--preview-window=up:45%",
                ]
            )
        )
    );
    assert_eq!(
        case.read_at(&case.logs.join("fzf.stdin.1")),
        format!("{}\n{}\n", one(&case), two(&case))
    );
    assert_eq!(
        case.read_at(&case.logs.join("fzf.stdin.2")),
        format!("0.9\t{}\n", two(&case))
    );
    assert_eq!(
        case.argv("music-similar"),
        expected_argv("music-similar", &["-k", "15", &one(&case)])
    );
    assert_eq!(
        case.argv("mpv"),
        expected_argv("mpv", &["--no-video", &two(&case)])
    );
}

#[test]
fn similar_uses_the_playing_track_and_the_k_argument() {
    let case = fixture("tui-similar-current");
    sequence(&case, &[&format!("0.9\t{}", one(&case))]);
    let output = case
        .command()
        .env("MUSIC_DIR", music_dir(&case))
        .env("FAKE_FZF_SEQ_FILE", case.path("sequence"))
        .env("FAKE_PLAYERCTL_LIST_CODE", "0")
        .env("FAKE_PLAYERCTL_OUT", "Artist - Title")
        .env("FAKE_MUSIC_SIMILAR_OUT", format!("0.9\t{}", one(&case)))
        .args(["similar", "5"])
        .output()
        .expect("run music-tui similar 5");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stderr(&output),
        "Analyzing similarities for current track…\n"
    );
    assert_eq!(
        case.argv("playerctl"),
        format!(
            "playerctl\nARG -l\nplayerctl\nARG metadata\nARG --format\nARG {{{{artist}}}} - {{{{title}}}}\n"
        )
    );
    assert_eq!(
        case.argv("music-similar"),
        expected_argv("music-similar", &["-k", "5"])
    );
    assert_eq!(
        case.argv("mpv"),
        expected_argv("mpv", &["--no-video", &one(&case)])
    );
}

#[test]
fn similar_reports_empty_results_and_missing_files() {
    let case = fixture("tui-similar-empty");
    sequence(&case, &[&one(&case)]);
    let output = case
        .command()
        .env("MUSIC_DIR", music_dir(&case))
        .env("FAKE_FZF_SEQ_FILE", case.path("sequence"))
        .env("FAKE_FD_OUT", format!("{}\n", one(&case)))
        .env("FAKE_MUSIC_SIMILAR_OUT", "")
        .args(["similar"])
        .output()
        .expect("run music-tui similar");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stderr(&output),
        "Analyzing similarities for one.flac…\n\
         music-tui: no similar tracks (run music-index first?)\n"
    );
    assert_eq!(case.argv("mpv"), "");

    let case = fixture("tui-similar-missing");
    sequence(
        &case,
        &[
            &one(&case),
            &format!("0.9\t{}/missing.flac", music_dir(&case)),
        ],
    );
    let output = case
        .command()
        .env("MUSIC_DIR", music_dir(&case))
        .env("FAKE_FZF_SEQ_FILE", case.path("sequence"))
        .env("FAKE_FD_OUT", format!("{}\n", one(&case)))
        .env(
            "FAKE_MUSIC_SIMILAR_OUT",
            format!("0.9\t{}/missing.flac", music_dir(&case)),
        )
        .args(["similar"])
        .output()
        .expect("run music-tui similar");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stderr(&output),
        format!(
            "Analyzing similarities for one.flac…\n\
             music-tui: file not found: {}/missing.flac\n",
            music_dir(&case)
        )
    );
    assert_eq!(case.argv("mpv"), "");
}

#[test]
fn similar_cancel_is_a_silent_success() {
    let case = fixture("tui-similar-cancel");
    let output = case
        .command()
        .env("MUSIC_DIR", music_dir(&case))
        .env("FAKE_PLAYERCTL_LIST_CODE", "1")
        .env("FAKE_FD_OUT", format!("{}\n", one(&case)))
        .args(["similar"])
        .output()
        .expect("run music-tui similar");
    assert_eq!(exited(&output), 0);
    assert_eq!(stderr(&output), "");
    assert_eq!(case.argv("music-similar"), "");
}

#[test]
fn missing_dependencies_die_before_touching_anything() {
    let case = fixture("tui-missing-similar");
    case.remove_fake("music-similar");
    let output = run(&case, &["similar"]);
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        "music-tui: command not found: music-similar\n"
    );
    assert_eq!(case.argv("fzf"), "");

    let case = fixture("tui-missing-mpv");
    case.remove_fake("mpv");
    let output = run(&case, &["similar"]);
    assert_eq!(exited(&output), 1);
    assert_eq!(stderr(&output), "music-tui: command not found: mpv\n");

    let case = fixture("tui-missing-highlevel");
    case.remove_fake("music-highlevel");
    let output = run(&case, &["classify"]);
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        "music-tui: command not found: music-highlevel\n"
    );

    let case = fixture("tui-missing-interactive");
    case.remove_fake("music-similar");
    let output = run(&case, &["interactive"]);
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        "music-tui: command not found: music-similar\n"
    );
}

#[test]
fn a_missing_fd_leaves_selections_empty() {
    let case = fixture("tui-no-fd");
    case.remove_fake("fd");
    let output = run(&case, &["similar"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stderr(&output), "");
    assert_eq!(
        case.read_at(&case.logs.join("fzf.stdin.1")),
        "",
        "fd's missing-command diagnostic is redirected away"
    );
}

#[test]
fn classify_opens_the_highlevel_output_in_fzf() {
    let case = fixture("tui-classify");
    sequence(&case, &["tag1"]);
    let output = case
        .command()
        .env("MUSIC_DIR", music_dir(&case))
        .env("FAKE_FZF_SEQ_FILE", case.path("sequence"))
        .env("FAKE_MUSIC_HIGHLEVEL_OUT", "tag1\ntag2")
        .args(["classify", &one(&case)])
        .output()
        .expect("run music-tui classify");
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "tag1\n");
    assert_eq!(stderr(&output), "Classifying one.flac…\n");
    assert_eq!(
        case.argv("music-highlevel"),
        expected_argv("music-highlevel", &[&one(&case)])
    );
    assert_eq!(
        case.argv("fzf"),
        expected_argv(
            "fzf",
            &[
                "--prompt=Classification",
                "--header",
                &one(&case),
                "--no-hscroll",
            ]
        )
    );
    assert_eq!(case.read_at(&case.logs.join("fzf.stdin.1")), "tag1\ntag2\n");
}

#[test]
fn classify_can_pick_a_track_and_rejects_missing_files() {
    let case = fixture("tui-classify-pick");
    sequence(&case, &[&one(&case), "tag"]);
    let output = case
        .command()
        .env("MUSIC_DIR", music_dir(&case))
        .env("FAKE_FZF_SEQ_FILE", case.path("sequence"))
        .env("FAKE_FD_OUT", format!("{}\n", one(&case)))
        .env("FAKE_MUSIC_HIGHLEVEL_OUT", "tag")
        .args(["c"])
        .output()
        .expect("run music-tui classify");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("fzf"),
        format!(
            "{}{}",
            expected_argv("fzf", &["--prompt=Pick track to classify > "]),
            expected_argv(
                "fzf",
                &[
                    "--prompt=Classification",
                    "--header",
                    &one(&case),
                    "--no-hscroll",
                ]
            )
        )
    );

    let case = fixture("tui-classify-missing");
    let output = run(&case, &["classify", "/no/such/file.flac"]);
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        "music-tui: file not found: /no/such/file.flac\n"
    );
    assert_eq!(case.argv("music-highlevel"), "");
}

#[test]
fn profile_renders_the_collection_and_index_metadata() {
    let case = fixture("tui-profile");
    let index = index_dir(&case);
    fs::create_dir_all(&index).expect("create index");
    case.write(&index.join("meta.json"), "{\"count\": 42, \"dim\": 128}\n");
    case.write(&index.join("index.ann"), "ANN");
    case.write(
        &index.join("tracks.jsonl"),
        "{\"path\": \"/m/ArtistA/Album/x.mp3\"}\n\
         {\"path\": \"/m/ArtistA/Album2/y.flac\"}\n\
         {\"path\": \"/m/ArtistB/z.mp3\"}\n\
         {\"path\": \"/m/nopath.jsonl\"}\n",
    );
    let output = case
        .command()
        .env("MUSIC_DIR", music_dir(&case))
        .env("FAKE_FD_OUT", format!("{}\n{}\n", one(&case), two(&case)))
        .env("FAKE_FD_EXEC_OUT", "1.5M\t/tmp/fake-music\n")
        .env("FAKE_PLAYERCTL_LIST_CODE", "0")
        .env("FAKE_PLAYERCTL_OUT", "Artist - Title")
        .env("FAKE_DU_OUT", "1.0K\t/some/index.ann\n")
        .env("FAKE_STAT_OUT", "2026-11-03 03:26:40.123456789 +0300\n")
        .args(["profile"])
        .output()
        .expect("run music-tui profile");
    assert_eq!(exited(&output), 0);
    let expected = format!(
        "=== Music Collection Profile ===\n\
         \n\
         Music directory: {}\n\
         \x20 Files:  2\n\
         \x20 Size:   1.5M\n\
         \n\
         Similarity index: {}\n\
         \x20 Tracks: 42\n\
         \x20 Dims:   128\n\
         \x20 Size:   1.0K\n\
         \x20 Date:   2026-11-03 03:26:40\n\
         \x20 Artists: 4\n\
         \n\
         Now playing: Artist - Title\n",
        music_dir(&case),
        index.to_string_lossy()
    );
    assert_eq!(stdout(&output), expected);
    assert_eq!(stderr(&output), "");
    assert_eq!(
        case.argv("fd"),
        format!(
            "{}{}",
            fd_arguments(&case, &[]),
            fd_arguments(&case, &["--exec", "du", "-ch", "{}", "+"])
        )
    );
    assert_eq!(
        case.argv("du"),
        expected_argv("du", &["-h", &index.join("index.ann").to_string_lossy()])
    );
    assert_eq!(
        case.argv("stat"),
        expected_argv(
            "stat",
            &["-c", "%y", &index.join("index.ann").to_string_lossy()]
        )
    );
    assert_eq!(
        case.argv("playerctl"),
        format!(
            "playerctl\nARG -l\nplayerctl\nARG metadata\nARG --format\nARG {{{{artist}}}} - {{{{title}}}}\n"
        )
    );
}

#[test]
fn profile_handles_a_missing_directory_and_an_unbuilt_index() {
    let case = fixture("tui-profile-empty");
    let output = case
        .command()
        .env("MUSIC_DIR", case.path("absent"))
        .env("FAKE_PLAYERCTL_LIST_CODE", "1")
        .args(["profile"])
        .output()
        .expect("run music-tui profile");
    assert_eq!(exited(&output), 0);
    let expected = format!(
        "=== Music Collection Profile ===\n\
         \n\
         Music directory: {}\n\
         \x20 (not found)\n\
         \n\
         Similarity index: {}\n\
         \x20 (not built — run music-index)\n\
         \n\
         Now playing: (none detected)\n",
        case.path("absent").to_string_lossy(),
        index_dir(&case).to_string_lossy()
    );
    assert_eq!(stdout(&output), expected);
    assert_eq!(case.argv("fd"), "");
}

#[test]
fn profile_reports_unknown_metadata_placeholders() {
    let case = fixture("tui-profile-unknown");
    let index = index_dir(&case);
    fs::create_dir_all(&index).expect("create index");
    case.write(&index.join("meta.json"), "{\"count\": 7}\n");
    case.write(&index.join("index.ann"), "ANN");
    case.write(&index.join("tracks.jsonl"), "not json\n");
    let output = case
        .command()
        .env("MUSIC_DIR", music_dir(&case))
        .env("FAKE_PLAYERCTL_LIST_CODE", "1")
        .args(["profile"])
        .output()
        .expect("run music-tui profile");
    assert_eq!(exited(&output), 0);
    let text = stdout(&output);
    assert!(text.contains("  Tracks: 7\n"), "{text}");
    assert!(text.contains("  Dims:   ?\n"), "{text}");
    assert!(text.contains("  Artists: ?\n"), "{text}");
    assert!(text.contains("  Files:  0\n"), "{text}");
    assert!(text.contains("  Size:   ?\n"), "{text}");
}

#[test]
fn profile_keeps_empty_values_for_a_malformed_meta_document() {
    let case = fixture("tui-profile-bad-meta");
    let index = index_dir(&case);
    fs::create_dir_all(&index).expect("create index");
    case.write(&index.join("meta.json"), "not json\n");
    let output = case
        .command()
        .env("MUSIC_DIR", music_dir(&case))
        .env("FAKE_PLAYERCTL_LIST_CODE", "1")
        .args(["profile"])
        .output()
        .expect("run music-tui profile");
    assert_eq!(exited(&output), 0);
    let text = stdout(&output);
    assert!(text.contains("  Tracks: \n"), "{text}");
    assert!(text.contains("  Dims:   \n"), "{text}");
}

#[test]
fn profile_shows_unknown_now_playing_when_metadata_fails() {
    let case = fixture("tui-profile-now");
    let output = case
        .command()
        .env("MUSIC_DIR", music_dir(&case))
        .env("FAKE_PLAYERCTL_LIST_CODE", "0")
        .env("FAKE_PLAYERCTL_CODE", "1")
        .args(["profile"])
        .output()
        .expect("run music-tui profile");
    assert_eq!(exited(&output), 0);
    assert!(stdout(&output).contains("Now playing: (unknown)\n"));
}

#[test]
fn interactive_drills_and_prints_the_zsh_local_declaration_noise() {
    let case = fixture("tui-interactive");
    let first = one(&case);
    let second = two(&case);
    let scored = format!("0.9\t{second}");
    sequence(&case, &[&first, &scored, &second, &scored, "", ""]);
    let output = case
        .command()
        .env("MUSIC_DIR", music_dir(&case))
        .env("FAKE_FZF_SEQ_FILE", case.path("sequence"))
        .env("FAKE_FD_OUT", format!("{first}\n{second}\n"))
        .env("FAKE_MUSIC_SIMILAR_OUT", scored.clone())
        .args(["interactive"])
        .output()
        .expect("run music-tui interactive");
    assert_eq!(exited(&output), 0);
    assert_eq!(stderr(&output), "");
    let quoted = scored.replace('\t', "\\t");
    assert_eq!(
        stdout(&output),
        format!(
            "results=$'{quoted}'\n\
             drill=$'{quoted}'\n\
             results=$'{quoted}'\n\
             drill={second}\n\
             results=$'{quoted}'\n\
             drill=$'{quoted}'\n"
        ),
        "the original leaks the previous results/drill values through bare `local` declarations"
    );
    let fzf = case.argv("fzf");
    assert!(fzf.contains("--prompt=Browse > "), "{fzf}");
    assert!(
        fzf.contains(&format!("--prompt=Similar: one.flac > ")),
        "{fzf}"
    );
    assert!(
        fzf.contains(&format!("--prompt=Similar: two.flac > ")),
        "{fzf}"
    );
    assert_eq!(
        case.argv("music-similar"),
        expected_argv("music-similar", &[&first])
            + &expected_argv("music-similar", &[&second])
            + &expected_argv("music-similar", &[&second])
            + &expected_argv("music-similar", &[&second])
    );
    assert_eq!(
        case.read_at(&case.logs.join("fzf.stdin.2")),
        format!("{scored}\n")
    );
    assert!(
        fzf.contains(PREVIEW_BROWSE),
        "browse preview missing: {fzf}"
    );
    assert!(fzf.contains(PREVIEW_DRILL), "drill preview missing: {fzf}");
}

#[test]
fn interactive_cancel_and_missing_dependencies_end_cleanly() {
    let case = fixture("tui-interactive-cancel");
    let output = case
        .command()
        .env("MUSIC_DIR", music_dir(&case))
        .env("FAKE_FD_OUT", format!("{}\n", one(&case)))
        .args(["interactive"])
        .output()
        .expect("run music-tui interactive");
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");

    let case = fixture("tui-interactive-no-mpv");
    case.remove_fake("mpv");
    let output = run(&case, &["interactive"]);
    assert_eq!(exited(&output), 1);
    assert_eq!(stderr(&output), "music-tui: command not found: mpv\n");
}
