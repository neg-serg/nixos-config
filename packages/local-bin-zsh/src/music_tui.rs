//! Rust port of `packages/local-bin/bin/music-tui`.
//!
//! The fzf-driven TUI around the MERT similarity index: `similar`, `classify`,
//! `profile` and `interactive`, plus the mode menu when no mode is given.
//!
//! Selection, line splitting and the profile formatting are native here; fzf,
//! fd, mpv, playerctl, music-similar and music-highlevel keep their original
//! argv, including the preview/bind scripts fzf runs itself. The profile used to
//! shell out to `python3 -c` for the index metadata; the JSON reading is now
//! in-process (`json`), so a missing python interpreter no longer empties the
//! Tracks/Dims/Artists lines. A malformed document still yields an empty
//! Tracks/Dims value and `?` for the artist count; the Python traceback the
//! original printed for a broken `meta.json` is not reproduced.

#![forbid(unsafe_code)]

use std::collections::HashSet;
use std::ffi::{OsStr, OsString};
use std::fs;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::path::Path;

use local_bin_zsh::{
    basename, before_first_dot, capture, command_not_found, count_newlines, die, err, first_field,
    first_fields, home, join_bytes, last_line, out, out_str, raw_args, run, var_nonempty,
    which_str, Captured, Site, Stderr, Stdin, Stdout,
};

mod json;

const USAGE: &str = include_str!("music_tui_usage.txt");

const ELLIPSIS: &str = "\u{2026}";
const PREVIEW_SIMILAR: &str =
    "p=\"$(echo {} | cut -f2-)\"; [ -n \"$p\" ] && music-highlevel \"$p\" 2>/dev/null | head -25";
const PREVIEW_BROWSE: &str = "\nf=\"{}\"\necho \"=== Similar tracks ===\"\nmusic-similar \"$f\" 2>/dev/null | head -8\necho \"\"\necho \"=== Highlevel ===\"\nmusic-highlevel \"$f\" 2>/dev/null | head -15\n";
const PREVIEW_DRILL: &str = "\np=\"$(echo {} | cut -f2-)\"\nif [ -n \"$p\" ] && [ -f \"$p\" ]; then\n  echo \"=== $p ===\"\n  music-highlevel \"$p\" 2>/dev/null | head -20\nfi\n";
const PREVIEW_MENU: &str = "\ncase {} in\n  similar)     echo \"Find similar tracks for current or selected track\";;\n  classify)    echo \"Run Essentia highlevel classification on a file\";;\n  profile)     echo \"Show collection statistics\";;\n  interactive) echo \"Browse music with similarity previews\";;\nesac";
const BIND_BROWSE_PLAY: &str = "ctrl-p:execute-silent(mpv --no-video {} &>/dev/null &)";
const BIND_BROWSE_TOGGLE: &str = "?:toggle-preview";
const BIND_DRILL_PLAY: &str =
    "ctrl-p:execute-silent(echo {} | cut -f2- | xargs -I % mpv --no-video \"%\" &>/dev/null &)";

fn music_dir() -> OsString {
    var_nonempty("MUSIC_DIR").unwrap_or_else(|| join_bytes(&home(), b"/music"))
}

fn index_dir() -> OsString {
    let cache = var_nonempty("XDG_CACHE_HOME").unwrap_or_else(|| join_bytes(&home(), b"/.cache"));
    join_bytes(&cache, b"/music-index")
}

fn find_audio(extra: &[OsString]) -> Captured {
    let mut arguments: Vec<OsString> = vec![
        OsString::from("-t"),
        OsString::from("f"),
        OsString::from("-e"),
        OsString::from("mp3"),
        OsString::from("-e"),
        OsString::from("flac"),
        OsString::from("-e"),
        OsString::from("wav"),
        OsString::from("-e"),
        OsString::from("ogg"),
        OsString::from("-e"),
        OsString::from("m4a"),
        OsString::from("-e"),
        OsString::from("opus"),
        OsString::from("-e"),
        OsString::from("aac"),
        OsString::from("-e"),
        OsString::from("aiff"),
        OsString::from("-e"),
        OsString::from("wma"),
        OsString::from("."),
        music_dir(),
    ];
    arguments.extend(extra.iter().cloned());
    capture(
        Site::Func("_find_audio", 1),
        "fd",
        &arguments,
        Stdin::Null,
        Stderr::Null,
    )
}

fn require(tool: &str) {
    if which_str(tool).is_none() {
        let mut message = b"command not found: ".to_vec();
        message.extend_from_slice(tool.as_bytes());
        die(&message);
    }
}

fn is_file(path: &OsStr) -> bool {
    fs::metadata(path)
        .map(|meta| meta.is_file())
        .unwrap_or(false)
}

fn is_dir(path: &OsStr) -> bool {
    fs::metadata(path)
        .map(|meta| meta.is_dir())
        .unwrap_or(false)
}

fn stderr_parts(parts: &[&[u8]]) {
    let mut message = Vec::new();
    for part in parts {
        message.extend_from_slice(part);
    }
    err(&message);
}

fn playerctl_running(site: Site) -> bool {
    capture(
        site,
        "playerctl",
        &[OsString::from("-l")],
        Stdin::Null,
        Stderr::Null,
    )
    .success()
}

fn playerctl_track(site: Site) -> Option<Vec<u8>> {
    let captured = capture(
        site,
        "playerctl",
        &[
            OsString::from("metadata"),
            OsString::from("--format"),
            OsString::from("{{artist}} - {{title}}"),
        ],
        Stdin::Null,
        Stderr::Null,
    );
    captured.success().then(|| captured.text())
}

/// The `_find_audio | fzf` picker shared by similar/classify.
fn pick_track(site: Site, prompt: &str, header: Option<&str>) -> Vec<u8> {
    let listed = find_audio(&[]);
    let mut arguments = vec![OsString::from(format!("--prompt={prompt}"))];
    if let Some(header) = header {
        arguments.push(OsString::from(format!("--header={header}")));
    }
    capture(
        site,
        "fzf",
        &arguments,
        Stdin::Bytes(listed.stdout),
        Stderr::Inherit,
    )
    .text()
}

fn after_first_tab(selection: &[u8]) -> Vec<u8> {
    match selection.iter().position(|byte| *byte == b'\t') {
        Some(position) => selection[position + 1..].to_vec(),
        None => selection.to_vec(),
    }
}

fn mode_similar(arguments: &[OsString]) -> i32 {
    require("music-similar");
    require("mpv");
    let k = match arguments.first() {
        Some(value) if !value.is_empty() => value.clone(),
        _ => OsString::from("15"),
    };

    let mut current = Vec::new();
    if playerctl_running(Site::Func("mode_similar", 5)) {
        current = playerctl_track(Site::Func("mode_similar", 6)).unwrap_or_default();
    }

    let mut audio = Vec::new();
    if current.is_empty() {
        audio = pick_track(
            Site::Func("mode_similar", 10),
            "Pick track > ",
            Some("No track playing"),
        );
        if audio.is_empty() {
            return 0;
        }
    }

    let captured = if !audio.is_empty() && is_file(OsStr::from_bytes(&audio)) {
        stderr_parts(&[
            b"Analyzing similarities for ",
            &basename(&audio),
            ELLIPSIS.as_bytes(),
            b"\n",
        ]);
        capture(
            Site::Func("mode_similar", 17),
            "music-similar",
            &[OsString::from("-k"), k, OsString::from_vec(audio)],
            Stdin::Null,
            Stderr::Null,
        )
    } else {
        stderr_parts(&[
            b"Analyzing similarities for current track",
            ELLIPSIS.as_bytes(),
            b"\n",
        ]);
        capture(
            Site::Func("mode_similar", 20),
            "music-similar",
            &[OsString::from("-k"), k],
            Stdin::Null,
            Stderr::Null,
        )
    };
    let results = if captured.success() {
        captured.text()
    } else {
        Vec::new()
    };
    if results.is_empty() {
        stderr_parts(&[b"music-tui: no similar tracks (run music-index first?)\n"]);
        return 0;
    }

    let mut input = results;
    input.push(b'\n');
    let selection = capture(
        Site::Func("mode_similar", 28),
        "fzf",
        &[
            OsString::from("--prompt=Similar > "),
            OsString::from("--header"),
            OsString::from("Enter=play | ESC=cancel"),
            OsString::from("--preview"),
            OsString::from(PREVIEW_SIMILAR),
            OsString::from("--preview-window=up:45%"),
        ],
        Stdin::Bytes(input),
        Stderr::Inherit,
    )
    .text();
    if selection.is_empty() {
        return 0;
    }

    let selected_path = OsString::from_vec(after_first_tab(&selection));
    if is_file(&selected_path) {
        run(
            Site::Func("mode_similar", 37),
            "mpv",
            &[OsString::from("--no-video"), selected_path],
            Stdin::Inherit,
            Stdout::Inherit,
            Stderr::Inherit,
        )
    } else {
        stderr_parts(&[
            b"music-tui: file not found: ",
            selected_path.as_bytes(),
            b"\n",
        ]);
        0
    }
}

fn mode_classify(arguments: &[OsString]) -> i32 {
    require("music-highlevel");
    let file = match arguments.first() {
        Some(value) if !value.is_empty() => value.clone(),
        _ => {
            let picked = pick_track(
                Site::Func("mode_classify", 5),
                "Pick track to classify > ",
                None,
            );
            if picked.is_empty() {
                return 0;
            }
            OsString::from_vec(picked)
        }
    };
    if !is_file(&file) {
        let mut message = b"file not found: ".to_vec();
        message.extend_from_slice(file.as_bytes());
        die(&message);
    }

    stderr_parts(&[
        b"Classifying ",
        &basename(file.as_bytes()),
        ELLIPSIS.as_bytes(),
        b"\n",
    ]);
    let classified = capture(
        Site::Func("mode_classify", 12),
        "music-highlevel",
        std::slice::from_ref(&file),
        Stdin::Null,
        Stderr::Null,
    );
    run(
        Site::Func("mode_classify", 13),
        "fzf",
        &[
            OsString::from("--prompt=Classification"),
            OsString::from("--header"),
            file,
            OsString::from("--no-hscroll"),
        ],
        Stdin::Bytes(classified.stdout),
        Stdout::Inherit,
        Stderr::Inherit,
    )
}

fn meta_value(path: &Path, key: &str) -> String {
    let text = match fs::read_to_string(path) {
        Ok(text) => text,
        Err(_) => return String::new(),
    };
    match json::parse(&text) {
        Ok(value) => match value.get(key) {
            Some(found) => found.python_repr(),
            None => "?".to_string(),
        },
        Err(_) => String::new(),
    }
}

/// The artist histogram Python computed from `tracks.jsonl`: the second-to-last
/// path component of each `path`, counted once.
fn artist_count(path: &Path) -> String {
    let text = match fs::read_to_string(path) {
        Ok(text) => text,
        Err(_) => return "?".to_string(),
    };
    let mut artists: HashSet<String> = HashSet::new();
    for line in text.lines() {
        let value = match json::parse(line) {
            Ok(value) => value,
            Err(_) => return "?".to_string(),
        };
        if !matches!(value, json::Value::Object(_)) {
            return "?".to_string();
        }
        let path_value = match value.get("path") {
            Some(json::Value::String(path)) => path.clone(),
            Some(_) => return "?".to_string(),
            None => String::new(),
        };
        let parts: Vec<&str> = path_value.trim_matches('/').split('/').collect();
        if parts.len() >= 2 {
            artists.insert(parts[parts.len() - 2].to_string());
        }
    }
    artists.len().to_string()
}

fn emit(parts: &[&[u8]]) {
    for part in parts {
        out(part);
    }
}

fn emit_line(parts: &[&[u8]]) {
    emit(parts);
    out(b"\n");
}

fn mode_profile() -> i32 {
    out_str("=== Music Collection Profile ===\n\n");

    let directory = music_dir();
    emit_line(&[b"Music directory: ", directory.as_bytes()]);
    if is_dir(&directory) {
        let files = find_audio(&[]);
        let count = count_newlines(&files.stdout).to_string();
        emit_line(&[b"  Files:  ", count.as_bytes()]);

        let sizes = find_audio(&[
            OsString::from("--exec"),
            OsString::from("du"),
            OsString::from("-ch"),
            OsString::from("{}"),
            OsString::from("+"),
        ]);
        // `fd --exec du ... | tail -1 | awk '{print $1}'`, with `${size:-?}`.
        let size = first_field(last_line(&sizes.stdout)).to_vec();
        let size = if size.is_empty() { b"?".to_vec() } else { size };
        emit_line(&[b"  Size:   ", size.as_slice()]);
    } else {
        out_str("  (not found)\n");
    }

    let index = index_dir();
    emit_line(&[b"\nSimilarity index: ", index.as_bytes()]);

    let meta = Path::new(&index).join("meta.json");
    if meta.is_file() {
        let count = meta_value(&meta, "count");
        let dim = meta_value(&meta, "dim");
        emit_line(&[b"  Tracks: ", count.as_bytes()]);
        emit_line(&[b"  Dims:   ", dim.as_bytes()]);
    }

    let index_ann = Path::new(&index).join("index.ann");
    if index_ann.is_file() {
        let sizes = capture(
            Site::Func("mode_profile", 25),
            "du",
            &[OsString::from("-h"), index_ann.as_os_str().to_os_string()],
            Stdin::Inherit,
            Stderr::Null,
        );
        let size = first_fields(&sizes.stdout);
        let dates = capture(
            Site::Func("mode_profile", 26),
            "stat",
            &[
                OsString::from("-c"),
                OsString::from("%y"),
                index_ann.as_os_str().to_os_string(),
            ],
            Stdin::Inherit,
            Stderr::Null,
        );
        let date = before_first_dot(&dates.stdout);
        emit_line(&[b"  Size:   ", size.as_slice()]);
        emit_line(&[b"  Date:   ", &date]);
    } else {
        out_str("  (not built \u{2014} run music-index)\n");
    }

    let tracks = Path::new(&index).join("tracks.jsonl");
    if tracks.is_file() {
        let artists = artist_count(&tracks);
        emit_line(&[b"  Artists: ", artists.as_bytes()]);
    }

    out(b"\n");
    if playerctl_running(Site::Func("mode_profile", 50)) {
        let now = playerctl_track(Site::Func("mode_profile", 52))
            .unwrap_or_else(|| b"(unknown)".to_vec());
        emit_line(&[b"Now playing: ", &now]);
    } else {
        out_str("Now playing: (none detected)\n");
    }
    0
}

fn browse_arguments() -> Vec<OsString> {
    vec![
        OsString::from("--prompt=Browse > "),
        OsString::from("--header"),
        OsString::from("Enter=show similars | Ctrl-P=play | ?=toggle preview | ESC=exit"),
        OsString::from("--bind"),
        OsString::from(BIND_BROWSE_PLAY),
        OsString::from("--bind"),
        OsString::from(BIND_BROWSE_TOGGLE),
        OsString::from("--preview"),
        OsString::from(PREVIEW_BROWSE),
        OsString::from("--preview-window=up:60%:hidden"),
    ]
}

fn drill_arguments(current: &OsStr) -> Vec<OsString> {
    let mut prompt = b"--prompt=Similar: ".to_vec();
    prompt.extend_from_slice(&basename(current.as_bytes()));
    prompt.extend_from_slice(b" > ");
    vec![
        OsString::from_vec(prompt),
        OsString::from("--header"),
        OsString::from("Enter=drill in | Ctrl-P=play | ESC=back"),
        OsString::from("--bind"),
        OsString::from(BIND_DRILL_PLAY),
        OsString::from("--preview"),
        OsString::from(PREVIEW_DRILL),
        OsString::from("--preview-window=up:50%"),
    ]
}

/// `local name` on a variable already declared in the same function prints
/// `name=<quoted value>` to stdout in zsh. The inner interactive loop declares
/// `results` and `drill` with bare `local` statements on every pass, so from the
/// second pass on the original leaks their previous values to stdout. The port
/// reproduces that output byte for byte; dropping it would change the script's
/// observed stdout.
fn zsh_assignment(name: &str, value: &[u8]) -> Vec<u8> {
    let mut line = Vec::new();
    line.extend_from_slice(name.as_bytes());
    line.push(b'=');
    line.extend_from_slice(&zsh_quoted(value));
    line.push(b'\n');
    line
}

/// The subset of zsh's assignment display the interactive values can hit:
/// plain for safe words, single quotes for other printable text, `$'...'` with
/// zsh's C escapes when control or non-ASCII bytes are present.
fn zsh_quoted(value: &[u8]) -> Vec<u8> {
    let needs_c_quotes = value
        .iter()
        .any(|byte| *byte < 0x20 || *byte == 0x7f || *byte >= 0x80);
    if needs_c_quotes {
        let mut quoted = b"$'".to_vec();
        for byte in value {
            match *byte {
                b'\t' => quoted.extend_from_slice(b"\\t"),
                b'\n' => quoted.extend_from_slice(b"\\n"),
                b'\'' => quoted.extend_from_slice(b"\\'"),
                b'\\' => quoted.extend_from_slice(b"\\\\"),
                0x20..=0x7e => quoted.push(*byte),
                byte if byte == 0x7f => quoted.extend_from_slice(b"\\C-?"),
                byte if byte < 0x20 => {
                    quoted.extend_from_slice(b"\\C-");
                    quoted.push(byte + 0x40);
                }
                byte => {
                    quoted.extend_from_slice(b"\\M-");
                    let low = byte & 0x7f;
                    match low {
                        0x20..=0x7e => quoted.push(low),
                        0x7f => quoted.extend_from_slice(b"\\C-?"),
                        _ => {
                            quoted.extend_from_slice(b"\\C-");
                            quoted.push(low + 0x40);
                        }
                    }
                }
            }
        }
        quoted.push(b'\'');
        quoted
    } else if value.is_empty() {
        b"''".to_vec()
    } else if value.iter().all(|byte| zsh_safe(*byte)) {
        value.to_vec()
    } else {
        let mut quoted = vec![b'\''];
        for byte in value {
            if *byte == b'\'' {
                quoted.extend_from_slice(b"'\\''");
            } else {
                quoted.push(*byte);
            }
        }
        quoted.push(b'\'');
        quoted
    }
}

fn zsh_safe(byte: u8) -> bool {
    byte.is_ascii_alphanumeric()
        || matches!(
            byte,
            b'-' | b'_' | b'.' | b'/' | b'+' | b',' | b'%' | b'@' | b'!' | b':'
        )
}

fn mode_interactive() -> i32 {
    require("music-similar");
    require("music-highlevel");
    require("mpv");

    // State for the zsh `local` re-declaration output (see zsh_assignment).
    let mut seen_results = false;
    let mut previous_results: Vec<u8> = Vec::new();
    let mut seen_drill = false;
    let mut previous_drill: Vec<u8> = Vec::new();

    loop {
        let listed = find_audio(&[]);
        let file = capture(
            Site::Func("mode_interactive", 8),
            "fzf",
            &browse_arguments(),
            Stdin::Bytes(listed.stdout),
            Stderr::Inherit,
        )
        .text();
        if file.is_empty() {
            break;
        }
        let mut current = OsString::from_vec(file);
        loop {
            if seen_results {
                out(&zsh_assignment("results", &previous_results));
            }
            seen_results = true;
            let captured = capture(
                Site::Func("mode_interactive", 28),
                "music-similar",
                std::slice::from_ref(&current),
                Stdin::Null,
                Stderr::Null,
            );
            let results = if captured.success() {
                captured.text()
            } else {
                Vec::new()
            };
            previous_results = results.clone();
            if results.is_empty() {
                stderr_parts(&[
                    b"music-tui: no similar tracks for ",
                    &basename(current.as_bytes()),
                    b"\n",
                ]);
                break;
            }
            if seen_drill {
                out(&zsh_assignment("drill", &previous_drill));
            }
            seen_drill = true;
            let mut input = results;
            input.push(b'\n');
            let drill = capture(
                Site::Func("mode_interactive", 33),
                "fzf",
                &drill_arguments(&current),
                Stdin::Bytes(input),
                Stderr::Inherit,
            )
            .text();
            previous_drill = drill.clone();
            if drill.is_empty() {
                break;
            }
            current = OsString::from_vec(after_first_tab(&drill));
            if !is_file(&current) {
                stderr_parts(&[b"music-tui: file not found: ", current.as_bytes(), b"\n"]);
                break;
            }
        }
    }
    0
}

fn menu() -> i32 {
    let list = b"similar\nclassify\nprofile\ninteractive\n".to_vec();
    let choice = capture(
        Site::Top(217),
        "fzf",
        &[
            OsString::from("--prompt=music-tui > "),
            OsString::from("--header"),
            OsString::from("similar | classify | profile | interactive"),
            OsString::from("--preview"),
            OsString::from(PREVIEW_MENU),
            OsString::from("--preview-window=up:2"),
        ],
        Stdin::Bytes(list),
        Stderr::Inherit,
    )
    .text();
    if choice.is_empty() {
        return 0;
    }
    match choice.as_slice() {
        b"similar" => mode_similar(&[]),
        b"classify" => mode_classify(&[]),
        b"profile" => mode_profile(),
        b"interactive" => mode_interactive(),
        _ => {
            let mut name = b"mode_".to_vec();
            name.extend_from_slice(&choice);
            command_not_found(Site::Top(230), &name)
        }
    }
}

fn main() {
    let arguments = raw_args();
    if let Some(first) = arguments.first() {
        if matches!(first.as_bytes(), b"-h" | b"--help") {
            out_str(USAGE);
            return;
        }
    }
    let mode = arguments.first().cloned().unwrap_or_default();
    let rest = if arguments.is_empty() {
        &arguments[..]
    } else {
        &arguments[1..]
    };
    let status = match mode.as_bytes() {
        b"" => menu(),
        b"similar" | b"s" => mode_similar(rest),
        b"classify" | b"c" => mode_classify(rest),
        b"profile" | b"p" | b"stats" => mode_profile(),
        b"interactive" | b"i" | b"browse" | b"b" => mode_interactive(),
        other => {
            let mut message = b"unknown mode: ".to_vec();
            message.extend_from_slice(other);
            message.extend_from_slice(b" (see -h for help)");
            die(&message)
        }
    };
    std::process::exit(status);
}
