//! Rust port of `packages/local-bin/scripts/music-highlevel`.
//!
//! The Python original is an argparse front end around Essentia's
//! `streaming_extractor_music`; it never implemented the classifiers itself.
//! The port keeps that split: the extractor is still spawned with
//! `streaming_extractor_music <audio> <temporary-dir>/highlevel.json`, stdout
//! and stderr of the extractor stay on `/dev/null`, and the JSON it writes is
//! read back and projected onto the same `path`/`highlevel` document.
//!
//! What is ported natively is everything the original did in Python:
//! argparse parsing (including its help/usage text, abbreviations, `--opt=value`
//! forms and error messages), `pathlib` input walking, `--top`/`--taxonomies`
//! projection, and the two output formats. The JSON happens to come from
//! `orjson` in the deployed interpreter, so parsing/serialization follows
//! `orjson`'s rules (see `json.rs` and `pyfmt.rs`).
//!
//! Deliberate deviations, all in diagnostic text rather than control flow:
//!   * `--help` wrapping uses `COLUMNS` or 80 columns; the original asks the
//!     controlling terminal for its width when `COLUMNS` is unset.
//!   * `--help` is never coloured (Python 3.14's argparse colours a tty).
//!   * a missing `streaming_extractor_music` or a non-object extractor output
//!     aborts with one diagnostic line and status 1 instead of a Python
//!     traceback (same status, different text).
//!
//! A missing, empty or malformed `highlevel.json` keeps the original's
//! per-track message and continues with the next track.

#![forbid(unsafe_code)]

use std::ffi::OsString;
use std::fs;
use std::io;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::DirBuilderExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use local_bin_scripts::env;
use local_bin_scripts::json::{self, Json};
use local_bin_scripts::pyfmt;
use local_bin_scripts::pypath::PyPath;
use local_bin_scripts::text;

const PROGRAM: &str = "music-highlevel";
const DESCRIPTION: &str = "Inspect Essentia highlevel classifiers for audio files";

const AUDIO_EXTENSIONS: &[&str] = &[
    ".mp3", ".flac", ".wav", ".ogg", ".m4a", ".opus", ".aac", ".wma", ".aiff", ".aif",
];

/// The common Essentia taxonomies the original shows when `--taxonomies` is
/// absent (or given with no values, which argparse turns into an empty list).
const DEFAULT_TAXONOMIES: &[&str] = &[
    "genre_dortmund",
    "genre_tzanetakis",
    "genre_rosamerica",
    "danceability",
    "moods_mirex",
    "moods_happiness",
    "moods_sadness",
    "moods_relaxed",
    "moods_aggressive",
    "tonal_atonal",
];

const DEFAULT_TOP: i128 = 3;

// ===========================================================================
// argparse model
// ===========================================================================

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Action {
    Help,
    Paths,
    Top,
    Taxonomies,
    Json,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Arity {
    /// argparse `nargs=None`: exactly one value.
    Single,
    /// argparse `nargs=0` (store_true and the help action).
    Zero,
    /// argparse `nargs='*'`.
    Star,
}

const OPTION_ACTIONS: &[Action] = &[Action::Help, Action::Top, Action::Taxonomies, Action::Json];

/// `parser._option_string_actions` in insertion order: the help action is added
/// first, the rest in declaration order. Abbreviation matching and the
/// "could match ..." list print in this order.
const OPTIONS: &[(&str, Action)] = &[
    ("-h", Action::Help),
    ("--help", Action::Help),
    ("--top", Action::Top),
    ("--taxonomies", Action::Taxonomies),
    ("--json", Action::Json),
];

impl Action {
    fn option_strings(self) -> &'static [&'static str] {
        match self {
            Action::Help => &["-h", "--help"],
            Action::Paths => &[],
            Action::Top => &["--top"],
            Action::Taxonomies => &["--taxonomies"],
            Action::Json => &["--json"],
        }
    }

    fn arity(self) -> Arity {
        match self {
            Action::Help | Action::Json => Arity::Zero,
            Action::Top => Arity::Single,
            Action::Paths | Action::Taxonomies => Arity::Star,
        }
    }

    fn metavar(self) -> &'static str {
        match self {
            Action::Paths => "paths",
            Action::Top => "TOP",
            Action::Taxonomies => "TAXONOMIES",
            Action::Help | Action::Json => "",
        }
    }

    fn help(self) -> &'static str {
        match self {
            Action::Paths => "audio files or directories; defaults to current track via playerctl",
            Action::Help => "show this help message and exit",
            Action::Top => "top probabilities per taxonomy to display",
            Action::Taxonomies => {
                "specific highlevel taxonomies to include (defaults to a common subset)"
            }
            Action::Json => "emit JSON per track",
        }
    }
}

/// `_get_action_name`: option strings joined with '/', else the metavar/dest.
fn action_name(action: Action) -> String {
    match action {
        Action::Help => "-h/--help".to_string(),
        other => other.option_strings()[0].to_string(),
    }
}

fn exact_option(argument: &[u8]) -> Option<Action> {
    OPTIONS
        .iter()
        .find_map(|(name, action)| (name.as_bytes() == argument).then_some(*action))
}

/// One possible interpretation of an option-looking argv element, mirroring the
/// tuples `_parse_optional` returns. `sep` is truthy when the explicit value
/// came after `=` (the short-option concatenation form has a falsy separator).
#[derive(Clone)]
struct RawMatch {
    action: Option<Action>,
    option_string: Vec<u8>,
    sep: bool,
    explicit: Option<Vec<u8>>,
}

fn split_at_equals(argument: &[u8]) -> (&[u8], Option<Vec<u8>>) {
    match argument.iter().position(|byte| *byte == b'=') {
        Some(position) => (
            &argument[..position],
            Some(argument[position + 1..].to_vec()),
        ),
        None => (argument, None),
    }
}

/// `_get_option_tuples`, the abbreviation/concatenation matcher.
fn option_tuples(argument: &[u8]) -> Vec<RawMatch> {
    let mut tuples = Vec::new();
    if argument.len() < 2 {
        return tuples;
    }
    let double_dash = argument[0] == b'-' && argument[1] == b'-';
    if double_dash {
        let (prefix, explicit) = split_at_equals(argument);
        for (name, action) in OPTIONS {
            if name.as_bytes().starts_with(prefix) {
                tuples.push(RawMatch {
                    action: Some(*action),
                    option_string: name.as_bytes().to_vec(),
                    sep: explicit.is_some(),
                    explicit: explicit.clone(),
                });
            }
        }
    } else if argument[0] == b'-' {
        let (option_prefix, explicit) = split_at_equals(argument);
        let short_prefix = &argument[..2];
        let short_explicit = &argument[2..];
        for (name, action) in OPTIONS {
            if name.as_bytes() == short_prefix {
                tuples.push(RawMatch {
                    action: Some(*action),
                    option_string: name.as_bytes().to_vec(),
                    sep: false,
                    explicit: Some(short_explicit.to_vec()),
                });
            } else if name.as_bytes().starts_with(option_prefix) {
                tuples.push(RawMatch {
                    action: Some(*action),
                    option_string: name.as_bytes().to_vec(),
                    sep: explicit.is_some(),
                    explicit: explicit.clone(),
                });
            }
        }
    }
    tuples
}

/// `_parse_optional`: `None` means "this argv element is an argument", a list
/// means "these are the option interpretations" (more than one is ambiguous,
/// one `None` action is an unknown option).
fn parse_optional(argument: &[u8]) -> Option<Vec<RawMatch>> {
    if argument.is_empty() {
        return None;
    }
    if argument[0] != b'-' {
        return None;
    }
    if let Some(action) = exact_option(argument) {
        return Some(vec![RawMatch {
            action: Some(action),
            option_string: argument.to_vec(),
            sep: false,
            explicit: None,
        }]);
    }
    if argument.len() == 1 {
        return None;
    }
    let (before, explicit) = split_at_equals(argument);
    if let Some(action) = exact_option(before) {
        return Some(vec![RawMatch {
            action: Some(action),
            option_string: before.to_vec(),
            sep: true,
            explicit,
        }]);
    }
    let tuples = option_tuples(argument);
    if !tuples.is_empty() {
        return Some(tuples);
    }
    // A value such as "-1" (or "-.5") is treated as a positional; an arbitrary
    // dash word is an unknown option that ends up in `unrecognized arguments`.
    if text::is_negative_number(argument) {
        return None;
    }
    if argument.contains(&b' ') {
        return None;
    }
    Some(vec![RawMatch {
        action: None,
        option_string: argument.to_vec(),
        sep: false,
        explicit: None,
    }])
}

/// `_match_argument`: how many following argv elements this option consumes.
fn match_argument(action: Action, pattern: &[u8]) -> Result<usize, String> {
    match action {
        Action::Help | Action::Json => Ok(0),
        Action::Top => {
            if pattern.first() == Some(&b'A') {
                Ok(1)
            } else {
                Err("expected one argument".to_string())
            }
        }
        Action::Taxonomies => Ok(pattern.iter().take_while(|byte| **byte == b'A').count()),
        Action::Paths => unreachable!("the positional is never matched as an optional"),
    }
}

fn argument_error(action: Action, message: &str) -> Vec<u8> {
    let mut out = format!("argument {}: ", action_name(action)).into_bytes();
    out.extend_from_slice(message.as_bytes());
    out
}

#[derive(Debug, Default)]
struct Parsed {
    top: i128,
    taxonomies: Vec<Vec<u8>>,
    json_output: bool,
    paths: Vec<Vec<u8>>,
}

fn take_action(
    action: Action,
    arguments: &[Vec<u8>],
    state: &mut Parsed,
    prog: &[u8],
    width: usize,
) -> Result<(), Vec<u8>> {
    match action {
        Action::Help => {
            env::out(help_text(&String::from_utf8_lossy(prog), width).as_bytes());
            std::process::exit(0);
        }
        Action::Paths => state.paths = arguments.to_vec(),
        Action::Json => state.json_output = true,
        Action::Taxonomies => state.taxonomies = arguments.to_vec(),
        Action::Top => {
            let Some(value) = arguments.first() else {
                return Err(argument_error(Action::Top, "expected one argument"));
            };
            let Some(parsed) = parse_python_int(value) else {
                return Err(argument_error(
                    Action::Top,
                    &format!("invalid int value: {}", python_repr(value)),
                ));
            };
            state.top = parsed;
        }
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)] // argparse OptionTuple consumer, kept 1:1
fn consume_optional(
    start: usize,
    argv: &[Vec<u8>],
    pattern: &[u8],
    options: &[Option<Vec<RawMatch>>],
    state: &mut Parsed,
    extras: &mut Vec<Vec<u8>>,
    prog: &[u8],
    width: usize,
) -> Result<usize, Vec<u8>> {
    let tuples = options[start].as_ref().expect("option index has matches");
    if tuples.len() > 1 {
        let mut message = Vec::from(&b"ambiguous option: "[..]);
        message.extend_from_slice(&argv[start]);
        message.extend_from_slice(b" could match ");
        for (index, tuple) in tuples.iter().enumerate() {
            if index > 0 {
                message.extend_from_slice(b", ");
            }
            message.extend_from_slice(&tuple.option_string);
        }
        return Err(message);
    }

    let first = &tuples[0];
    let Some(mut action) = first.action else {
        extras.push(argv[start].clone());
        return Ok(start + 1);
    };

    let mut option_string = first.option_string.clone();
    let mut sep = first.sep;
    let mut explicit = first.explicit.clone();
    let mut action_tuples: Vec<(Action, Vec<Vec<u8>>)> = Vec::new();
    let stop;
    loop {
        if let Some(value) = explicit.clone() {
            let arg_count = match match_argument(action, b"A") {
                Ok(count) => count,
                Err(message) => return Err(argument_error(action, &message)),
            };
            if arg_count == 0 && option_string.get(1) != Some(&b'-') && !value.is_empty() {
                // A single-dash option that takes no value: argparse tries to
                // read the tail as concatenated short options ("-hx").
                if sep || value[0] == b'-' {
                    return Err(argument_error(
                        action,
                        &format!("ignored explicit argument {}", python_repr(&value)),
                    ));
                }
                action_tuples.push((action, Vec::new()));
                let mut combined = vec![b'-', value[0]];
                let rest = &value[1..];
                match exact_option(&combined) {
                    Some(next) => {
                        action = next;
                        option_string = std::mem::take(&mut combined);
                        if rest.is_empty() {
                            sep = false;
                            explicit = None;
                        } else if rest[0] == b'=' {
                            sep = true;
                            explicit = Some(rest[1..].to_vec());
                        } else {
                            sep = false;
                            explicit = Some(rest.to_vec());
                        }
                    }
                    None => {
                        let mut extra = vec![b'-'];
                        extra.extend_from_slice(&value);
                        extras.push(extra);
                        stop = start + 1;
                        break;
                    }
                }
            } else if arg_count == 1 {
                action_tuples.push((action, vec![value]));
                stop = start + 1;
                break;
            } else {
                return Err(argument_error(
                    action,
                    &format!("ignored explicit argument {}", python_repr(&value)),
                ));
            }
        } else {
            let arg_count = match match_argument(action, &pattern[start + 1..]) {
                Ok(count) => count,
                Err(message) => return Err(argument_error(action, &message)),
            };
            stop = start + 1 + arg_count;
            action_tuples.push((action, argv[start + 1..stop].to_vec()));
            break;
        }
    }

    for (action, arguments) in action_tuples {
        take_action(action, &arguments, state, prog, width)?;
    }
    Ok(stop)
}

/// The leading run of positional/`--` markers a positional may take.
fn positional_run(pattern: &[u8]) -> usize {
    pattern
        .iter()
        .take_while(|byte| **byte == b'A' || **byte == b'-')
        .count()
}

fn take_positionals(argv: &[Vec<u8>], pattern: &[u8], start: usize, count: usize) -> Vec<Vec<u8>> {
    let mut arguments: Vec<Vec<u8>> = argv[start..start + count].to_vec();
    if pattern[start..start + count].contains(&b'-') {
        // argparse strips the "--" separator from the positional's values.
        if let Some(position) = arguments.iter().position(|argument| argument == b"--") {
            arguments.remove(position);
        }
    }
    arguments
}

/// `parser.parse_args` for this one positional and four options.
fn parse_args(argv: &[Vec<u8>], prog: &[u8], width: usize) -> Result<Parsed, Vec<u8>> {
    let mut pattern: Vec<u8> = Vec::with_capacity(argv.len());
    let mut options: Vec<Option<Vec<RawMatch>>> = vec![None; argv.len()];
    let mut index = 0;
    while index < argv.len() {
        if argv[index] == b"--" {
            pattern.push(b'-');
            index += 1;
            while index < argv.len() {
                pattern.push(b'A');
                index += 1;
            }
            break;
        }
        match parse_optional(&argv[index]) {
            None => pattern.push(b'A'),
            Some(tuples) => {
                options[index] = Some(tuples);
                pattern.push(b'O');
            }
        }
        index += 1;
    }

    let mut state = Parsed {
        top: DEFAULT_TOP,
        ..Parsed::default()
    };
    let mut extras: Vec<Vec<u8>> = Vec::new();
    let mut positionals_available = true;
    let max_option = options.iter().rposition(|entry| entry.is_some());
    let mut start = 0;

    if let Some(max_option) = max_option {
        while start <= max_option {
            let mut next_option = start;
            while next_option <= max_option && options[next_option].is_none() {
                next_option += 1;
            }
            if start != next_option && positionals_available {
                let count = positional_run(&pattern[start..]);
                if count > 0 {
                    state.paths = take_positionals(argv, &pattern, start, count);
                    positionals_available = false;
                    start += count;
                    continue;
                }
            }
            if options[start].is_none() {
                extras.extend_from_slice(&argv[start..next_option]);
                start = next_option;
            }
            start = consume_optional(
                start,
                argv,
                &pattern,
                &options,
                &mut state,
                &mut extras,
                prog,
                width,
            )?;
        }
    }

    if positionals_available {
        let count = positional_run(&pattern[start..]);
        if count > 0 {
            state.paths = take_positionals(argv, &pattern, start, count);
            start += count;
        }
    }
    extras.extend_from_slice(&argv[start..]);

    if !extras.is_empty() {
        let mut message = Vec::from(&b"unrecognized arguments: "[..]);
        for (index, extra) in extras.iter().enumerate() {
            if index > 0 {
                message.push(b' ');
            }
            message.extend_from_slice(extra);
        }
        return Err(message);
    }
    Ok(state)
}

// ===========================================================================
// ArgumentParser-compatible help formatting
// ===========================================================================

struct HelpLayout {
    width: usize,
    max_help_position: usize,
}

fn display_width(text: &str) -> usize {
    text.chars().count()
}

/// Python's `textwrap.wrap` (default options) as `_split_lines` uses it: the
/// text is whitespace-collapsed, then greedy filled; a word longer than the
/// width is broken to fill the rest of the current line and continued on the
/// next one. The help strings contain no hyphens, so `break_on_hyphens` never
/// changes a break point and is not modelled.
fn wrap_words(text: &str, width: usize) -> Vec<String> {
    let width = width.max(1);
    let mut chunks: Vec<String> = Vec::new();
    let mut words = text.split_whitespace().peekable();
    while let Some(word) = words.next() {
        chunks.push(word.to_string());
        if words.peek().is_some() {
            chunks.push(" ".to_string());
        }
    }
    chunks.reverse();

    let mut lines: Vec<String> = Vec::new();
    while !chunks.is_empty() {
        let mut current: Vec<String> = Vec::new();
        let mut current_width = 0usize;
        if chunks
            .last()
            .map(|chunk| chunk.trim().is_empty())
            .unwrap_or(false)
            && !lines.is_empty()
        {
            chunks.pop();
        }
        while let Some(chunk) = chunks.last() {
            let chunk_width = display_width(chunk);
            if current_width + chunk_width <= width {
                current.push(chunks.pop().expect("chunk"));
                current_width += chunk_width;
            } else {
                break;
            }
        }
        if let Some(chunk) = chunks.last() {
            if display_width(chunk) > width {
                let space_left = width - current_width;
                if space_left > 0 {
                    let piece: String = chunk.chars().take(space_left).collect();
                    let remainder: String = chunk.chars().skip(space_left).collect();
                    current.push(piece);
                    if remainder.is_empty() {
                        chunks.pop();
                    } else {
                        *chunks.last_mut().expect("long chunk") = remainder;
                    }
                }
            }
        }
        if current
            .last()
            .map(|chunk| chunk.trim().is_empty())
            .unwrap_or(false)
        {
            current.pop();
        }
        if !current.is_empty() {
            lines.push(current.concat());
        }
    }
    if lines.is_empty() {
        lines.push(String::new());
    }
    lines
}

fn usage_metavar(action: Action) -> String {
    match action.arity() {
        Arity::Zero => action.option_strings()[0].to_string(),
        Arity::Single => format!("{} {}", action.option_strings()[0], action.metavar()),
        Arity::Star if action == Action::Paths => format!("[{} ...]", action.metavar()),
        Arity::Star => format!("{} [{} ...]", action.option_strings()[0], action.metavar()),
    }
}

fn usage_part(action: Action) -> String {
    let part = usage_metavar(action);
    if action == Action::Paths {
        part
    } else {
        format!("[{part}]")
    }
}

fn invocation(action: Action) -> String {
    match action.arity() {
        Arity::Zero => action.option_strings().join(", "),
        Arity::Single => format!(
            "{} {}",
            action.option_strings().join(", "),
            action.metavar()
        ),
        Arity::Star if action == Action::Paths => action.metavar().to_string(),
        Arity::Star => format!(
            "{} [{} ...]",
            action.option_strings().join(", "),
            action.metavar()
        ),
    }
}

impl HelpLayout {
    fn new(width: usize) -> Self {
        let width = width.max(1);
        let max_help_position = 24.min(width.saturating_sub(20).max(4));
        Self {
            width,
            max_help_position,
        }
    }

    fn action_max_length() -> usize {
        let mut maximum = 0;
        for action in [
            Action::Help,
            Action::Paths,
            Action::Top,
            Action::Taxonomies,
            Action::Json,
        ] {
            maximum = maximum.max(display_width(&invocation(action)) + 2);
        }
        maximum
    }

    fn usage_text(&self, prog: &str) -> String {
        let prefix = "usage: ";
        let optionals: Vec<String> = OPTION_ACTIONS.iter().map(|a| usage_part(*a)).collect();
        let positionals: Vec<String> = vec![usage_part(Action::Paths)];
        let mut parts = Vec::new();
        parts.push(prog.to_string());
        parts.extend(optionals.iter().cloned());
        parts.extend(positionals.iter().cloned());
        let usage = parts.join(" ");
        let text_width = self.width;
        let usage = if display_width(prefix) + display_width(&usage) > text_width {
            let prog_len = display_width(prog);
            let mut first = vec![prog.to_string()];
            first.extend(optionals.iter().cloned());
            if (display_width(prefix) + prog_len) as f64 <= 0.75 * text_width as f64 {
                let indent = " ".repeat(display_width(prefix) + prog_len + 1);
                let mut lines = get_lines(&first, &indent, Some(prefix), text_width);
                lines.extend(get_lines(&positionals, &indent, None, text_width));
                lines.join("\n")
            } else {
                let indent = " ".repeat(display_width(prefix));
                let mut combined = optionals.clone();
                combined.extend(positionals.iter().cloned());
                let mut lines = get_lines(&combined, &indent, None, text_width);
                if lines.len() > 1 {
                    lines = get_lines(&optionals, &indent, None, text_width);
                    lines.extend(get_lines(&positionals, &indent, None, text_width));
                }
                let mut wrapped = vec![prog.to_string()];
                wrapped.extend(lines);
                wrapped.join("\n")
            }
        } else {
            usage
        };
        format!("{prefix}{usage}\n\n")
    }

    fn format_action(&self, action: Action, action_max_length: usize) -> String {
        let help_position = (action_max_length + 2).min(self.max_help_position);
        let help_width = self.width.saturating_sub(help_position).max(11);
        let action_width = help_position.saturating_sub(4);
        let header = invocation(action);
        let mut out = String::from("  ");
        let indent_first = if display_width(&header) <= action_width {
            out.push_str(&format!("{header:<action_width$}"));
            out.push_str("  ");
            0
        } else {
            out.push_str(&header);
            out.push('\n');
            help_position
        };
        let help_lines = wrap_words(action.help(), help_width);
        out.push_str(&" ".repeat(indent_first));
        out.push_str(&help_lines[0]);
        out.push('\n');
        for line in &help_lines[1..] {
            out.push_str(&" ".repeat(help_position));
            out.push_str(line);
            out.push('\n');
        }
        out
    }

    fn section(&self, heading: &str, actions: &[Action], action_max_length: usize) -> String {
        let mut items = String::new();
        for action in actions {
            items.push_str(&self.format_action(*action, action_max_length));
        }
        format!("\n{heading}:\n{items}\n")
    }

    fn help_text(&self, prog: &str) -> String {
        let action_max_length = Self::action_max_length();
        let mut text = self.usage_text(prog);
        text.push_str(&format!(
            "{}\n\n",
            wrap_words(DESCRIPTION, self.width.max(11)).join("\n")
        ));
        text.push_str(&self.section("positional arguments", &[Action::Paths], action_max_length));
        text.push_str(&self.section("options", OPTION_ACTIONS, action_max_length));
        collapse_newline_runs(&text)
    }
}

/// Python's `_get_lines` inside `_format_usage`.
fn get_lines(
    parts: &[String],
    indent: &str,
    prefix: Option<&str>,
    text_width: usize,
) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    let mut line: Vec<&str> = Vec::new();
    let indent_width = display_width(indent);
    let mut line_width = match prefix {
        Some(prefix) => display_width(prefix).saturating_sub(1),
        None => indent_width.saturating_sub(1),
    };
    for part in parts {
        let part_width = display_width(part);
        if line_width + 1 + part_width > text_width && !line.is_empty() {
            lines.push(format!("{indent}{}", line.join(" ")));
            line.clear();
            line_width = indent_width.saturating_sub(1);
        }
        line.push(part.as_str());
        line_width += part_width + 1;
    }
    if !line.is_empty() {
        lines.push(format!("{indent}{}", line.join(" ")));
    }
    if prefix.is_some() && !lines.is_empty() {
        lines[0] = lines[0].chars().skip(indent_width).collect();
    }
    lines
}

/// `HelpFormatter.format_help` tail: collapse blank-line runs, strip the
/// surrounding newlines, end with exactly one.
fn collapse_newline_runs(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut newlines = 0usize;
    for character in text.chars() {
        if character == '\n' {
            newlines += 1;
            if newlines > 2 {
                continue;
            }
        } else {
            newlines = 0;
        }
        out.push(character);
    }
    format!("{}\n", out.trim_matches('\n'))
}

fn help_text(prog: &str, width: usize) -> String {
    HelpLayout::new(width).help_text(prog)
}

fn usage_text(prog: &str, width: usize) -> String {
    HelpLayout::new(width).usage_text(prog)
}

// ===========================================================================
// Python-compatible scalar formatting
// ===========================================================================

/// Python `int(bytes)`: optional sign, decimal digits with single underscores
/// between them, surrounding whitespace. Values beyond i128 saturate, which is
/// enough because the result is only compared with zero and used as a slice
/// length. Non-ASCII digits (Python accepts them) are not recognised.
fn parse_python_int(bytes: &[u8]) -> Option<i128> {
    let text = std::str::from_utf8(bytes).ok()?.trim();
    let (negative, digits) = match text.as_bytes().first()? {
        b'+' => (false, &text[1..]),
        b'-' => (true, &text[1..]),
        _ => (false, text),
    };
    if digits.is_empty() {
        return None;
    }
    let mut value: i128 = 0;
    let mut saw_digit = false;
    let mut previous_underscore = false;
    let mut characters = digits.chars().peekable();
    while let Some(character) = characters.next() {
        match character {
            '0'..='9' => {
                saw_digit = true;
                previous_underscore = false;
                value = value
                    .saturating_mul(10)
                    .saturating_add((character as u8 - b'0') as i128);
            }
            '_' => {
                // Python allows underscores only between digits.
                if !saw_digit || previous_underscore {
                    return None;
                }
                match characters.peek() {
                    Some(next) if next.is_ascii_digit() => {}
                    _ => return None,
                }
                previous_underscore = true;
            }
            _ => return None,
        }
    }
    if !saw_digit || previous_underscore {
        return None;
    }
    Some(if negative { -value } else { value })
}

#[derive(Clone, Copy)]
enum ReprUnit {
    Character(char),
    InvalidByte(u8),
}

fn repr_units(bytes: &[u8]) -> Vec<ReprUnit> {
    let mut units = Vec::with_capacity(bytes.len());
    let mut rest = bytes;
    while !rest.is_empty() {
        match std::str::from_utf8(rest) {
            Ok(text) => {
                units.extend(text.chars().map(ReprUnit::Character));
                break;
            }
            Err(error) => {
                let valid = error.valid_up_to();
                let text = std::str::from_utf8(&rest[..valid]).expect("valid UTF-8 prefix");
                units.extend(text.chars().map(ReprUnit::Character));
                let invalid_width = error.error_len().unwrap_or(rest.len() - valid);
                for byte in &rest[valid..valid + invalid_width] {
                    units.push(ReprUnit::InvalidByte(*byte));
                }
                rest = &rest[valid + invalid_width..];
            }
        }
    }
    units
}

/// Python `repr(bytes.decode('utf-8', 'surrogateescape'))`, as used by argparse
/// when it quotes an offending value.
fn python_repr(bytes: &[u8]) -> String {
    let units = repr_units(bytes);
    let has_single = units
        .iter()
        .any(|unit| matches!(unit, ReprUnit::Character('\'')));
    let has_double = units
        .iter()
        .any(|unit| matches!(unit, ReprUnit::Character('"')));
    let quote = if has_single && !has_double { '"' } else { '\'' };
    let mut out = String::with_capacity(bytes.len() + 2);
    out.push(quote);
    for unit in units {
        match unit {
            ReprUnit::InvalidByte(byte) => out.push_str(&format!("\\udc{byte:02x}")),
            ReprUnit::Character(character) => match character {
                '\\' => out.push_str("\\\\"),
                '\n' => out.push_str("\\n"),
                '\r' => out.push_str("\\r"),
                '\t' => out.push_str("\\t"),
                value if value == quote => {
                    out.push('\\');
                    out.push(quote);
                }
                value if (value as u32) < 0x20 || value as u32 == 0x7f => {
                    out.push_str(&format!("\\x{:02x}", value as u32));
                }
                value => out.push(value),
            },
        }
    }
    out.push(quote);
    out
}

/// Python `float(text)` for the string-valued probabilities a misbehaving
/// extractor could emit. Underscore-separated digits are not supported.
fn parse_python_float(text: &str) -> Option<f64> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return None;
    }
    let (sign, rest) = match trimmed.strip_prefix('-') {
        Some(rest) => (-1.0, rest),
        None => (1.0, trimmed.strip_prefix('+').unwrap_or(trimmed)),
    };
    if rest.eq_ignore_ascii_case("inf") || rest.eq_ignore_ascii_case("infinity") {
        return Some(sign * f64::INFINITY);
    }
    if rest.eq_ignore_ascii_case("nan") {
        return Some(f64::NAN);
    }
    let value: f64 = trimmed.parse().ok()?;
    Some(value)
}

// ===========================================================================
// Extractor output projection
// ===========================================================================

#[derive(Debug, Clone, PartialEq)]
struct Candidate {
    label: String,
    score: f64,
}

#[derive(Debug, Clone, PartialEq)]
enum Value {
    Text(String),
    Number(f64),
}

#[derive(Debug, Clone, PartialEq, Default)]
struct Entry {
    candidates: Option<Vec<Candidate>>,
    score: Option<f64>,
    value: Option<Value>,
}

impl Entry {
    fn is_empty(&self) -> bool {
        self.candidates.is_none() && self.score.is_none() && self.value.is_none()
    }

    /// Same key order as the Python dict literal: probability first (either
    /// `candidates` or `score`), then `value`.
    fn into_json(self) -> Json {
        let mut fields: Vec<(String, Json)> = Vec::new();
        if let Some(candidates) = self.candidates {
            let items = candidates
                .into_iter()
                .map(|candidate| {
                    Json::Obj(vec![
                        ("label".to_string(), Json::Str(candidate.label)),
                        ("score".to_string(), Json::Num(candidate.score)),
                    ])
                })
                .collect();
            fields.push(("candidates".to_string(), Json::Arr(items)));
        }
        if let Some(score) = self.score {
            fields.push(("score".to_string(), Json::Num(score)));
        }
        if let Some(value) = self.value {
            let json = match value {
                Value::Text(text) => Json::Str(text),
                Value::Number(number) => Json::Num(number),
            };
            fields.push(("value".to_string(), json));
        }
        Json::Obj(fields)
    }
}

enum Selection<'a> {
    Defaults,
    Explicit(&'a [Vec<u8>]),
}

impl Selection<'_> {
    fn contains(&self, name: &str) -> bool {
        match self {
            Selection::Defaults => DEFAULT_TAXONOMIES.contains(&name),
            Selection::Explicit(chosen) => chosen.iter().any(|entry| entry == name.as_bytes()),
        }
    }
}

fn field<'a>(fields: &'a [(String, Json)], key: &str) -> Option<&'a Json> {
    fields
        .iter()
        .find_map(|(name, value)| (name == key).then_some(value))
}

/// `isinstance(value, (int, float))`: Python booleans are ints too.
fn is_python_number(value: &Json) -> bool {
    matches!(value, Json::Int(_) | Json::Num(_) | Json::Bool(_))
}

fn json_number(value: &Json) -> Option<f64> {
    match value {
        Json::Int(number) => Some(*number as f64),
        Json::Num(number) => Some(*number),
        Json::Bool(flag) => Some(if *flag { 1.0 } else { 0.0 }),
        _ => None,
    }
}

/// `float(value)` for every JSON kind: strings are parsed, numbers and booleans
/// convert, everything else raises in Python (and empties the candidate list).
fn python_float(value: &Json) -> Option<f64> {
    match value {
        Json::Str(text) => parse_python_float(text),
        other => json_number(other),
    }
}

fn truncate_probs(probabilities: &[(String, Json)], top: i128) -> Vec<Candidate> {
    let mut items: Vec<Candidate> = Vec::with_capacity(probabilities.len());
    for (label, score) in probabilities {
        let Some(score) = python_float(score) else {
            return Vec::new();
        };
        items.push(Candidate {
            label: label.clone(),
            score,
        });
    }
    // Python's sort is stable and `reverse=True` keeps equal scores in their
    // insertion order; NaN compares as equal to everything (it never does).
    items.sort_by(|left, right| {
        right
            .score
            .partial_cmp(&left.score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    if top > 0 {
        let limit = usize::try_from(top).unwrap_or(usize::MAX);
        items.truncate(limit);
    }
    items
}

fn extract_highlevel(
    highlevel: &[(String, Json)],
    selection: &Selection,
    top: i128,
) -> Vec<(String, Entry)> {
    let mut result: Vec<(String, Entry)> = Vec::new();
    for (name, payload) in highlevel {
        if !selection.contains(name) {
            continue;
        }
        let Json::Obj(fields) = payload else {
            continue;
        };
        let mut entry = Entry::default();
        match field(fields, "probability") {
            Some(Json::Obj(probabilities)) => {
                let candidates = truncate_probs(probabilities, top);
                if !candidates.is_empty() {
                    entry.candidates = Some(candidates);
                }
            }
            Some(probability) if is_python_number(probability) => {
                entry.score = json_number(probability);
            }
            _ => {}
        }
        if let Some(value) = field(fields, "value") {
            match value {
                Json::Str(text) => entry.value = Some(Value::Text(text.clone())),
                other if is_python_number(other) => {
                    entry.value = Some(Value::Number(json_number(other).expect("number")))
                }
                _ => {}
            }
        }
        if !entry.is_empty() {
            result.push((name.clone(), entry));
        }
    }
    result
}

// ===========================================================================
// Input discovery
// ===========================================================================

fn audio_extension(path: &PyPath) -> bool {
    let suffix = path.suffix();
    let lowered: Vec<u8> = suffix
        .iter()
        .map(|byte| byte.to_ascii_lowercase())
        .collect();
    AUDIO_EXTENSIONS
        .iter()
        .any(|extension| extension.as_bytes() == lowered)
}

fn walk_inputs(inputs: &[PyPath]) -> Vec<PyPath> {
    let mut files: Vec<PyPath> = Vec::new();
    for path in inputs {
        if path.is_dir() {
            for child in path.rglob_descendants() {
                if child.is_file() && audio_extension(&child) {
                    files.push(child);
                }
            }
        } else if path.is_file() {
            files.push(path.clone());
        }
    }
    files
}

fn hex_value(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

/// `urllib.parse.unquote` for bytes; the caller decodes the result as UTF-8.
fn percent_decode(bytes: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'%' && index + 2 < bytes.len() {
            if let (Some(high), Some(low)) =
                (hex_value(bytes[index + 1]), hex_value(bytes[index + 2]))
            {
                out.push(high * 16 + low);
                index += 3;
                continue;
            }
        }
        out.push(bytes[index]);
        index += 1;
    }
    out
}

/// `urlparse(url).path` for a `file://` URL, percent-decoded.
fn file_url_path(url: &[u8]) -> Option<Vec<u8>> {
    let rest = url.strip_prefix(b"file://")?;
    let authority_end = rest
        .iter()
        .position(|byte| *byte == b'/')
        .unwrap_or(rest.len());
    let path_and_more = &rest[authority_end..];
    let end = path_and_more
        .iter()
        .position(|byte| *byte == b'?' || *byte == b'#')
        .unwrap_or(path_and_more.len());
    let decoded = percent_decode(&path_and_more[..end]);
    Some(String::from_utf8_lossy(&decoded).into_owned().into_bytes())
}

/// `playerctl metadata xesam:url`, decoded like `text=True` would and
/// `str.strip()`ed; any failure means "no current track".
fn current_track() -> Vec<u8> {
    let output = Command::new("playerctl")
        .arg("metadata")
        .arg("xesam:url")
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .output();
    match output {
        Ok(output) if output.status.success() => match String::from_utf8(output.stdout) {
            Ok(text) => text.trim().as_bytes().to_vec(),
            Err(_) => Vec::new(),
        },
        _ => Vec::new(),
    }
}

// ===========================================================================
// Extractor invocation
// ===========================================================================

static TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

fn unique_suffix() -> u64 {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    (now.as_secs() << 20)
        ^ (now.subsec_nanos() as u64)
        ^ ((std::process::id() as u64) << 40)
        ^ TEMP_COUNTER.fetch_add(1, Ordering::Relaxed)
}

/// `tempfile.TemporaryDirectory()`: a private directory below `$TMPDIR` (or
/// `/tmp`), removed recursively when the track is done.
struct TemporaryDirectory {
    path: PathBuf,
}

impl TemporaryDirectory {
    fn new() -> io::Result<Self> {
        let base = match env::var_bytes("TMPDIR") {
            Some(value) if !value.is_empty() => PathBuf::from(env::os_string(&value)),
            _ => PathBuf::from("/tmp"),
        };
        let base = if base.is_dir() {
            base
        } else {
            PathBuf::from("/tmp")
        };
        for attempt in 0..64u64 {
            let name = format!(
                "tmp{:08x}{:04x}{:02x}",
                unique_suffix(),
                std::process::id() as u16,
                attempt
            );
            let candidate = base.join(name);
            match fs::DirBuilder::new().mode(0o700).create(&candidate) {
                Ok(()) => return Ok(Self { path: candidate }),
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(error),
            }
        }
        Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            "temporary directory name collision",
        ))
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TemporaryDirectory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

fn message_with_path(prefix: &[u8], audio: &PyPath, suffix: &[u8]) -> Vec<u8> {
    let mut message = prefix.to_vec();
    message.extend_from_slice(audio.as_bytes());
    message.extend_from_slice(suffix);
    message
}

fn describe_io_error(error: &io::Error, path: &Path) -> String {
    match error.raw_os_error() {
        Some(code) => format!(
            "[Errno {code}] {}: {}",
            env::os_error_text(error),
            python_repr(path.as_os_str().as_bytes())
        ),
        None => error.to_string(),
    }
}

fn run_extractor(audio: &PyPath) -> Option<Json> {
    let temporary = match TemporaryDirectory::new() {
        Ok(directory) => directory,
        Err(error) => {
            let mut message =
                Vec::from(&b"[music-highlevel] cannot create a temporary directory: "[..]);
            message.extend_from_slice(error.to_string().as_bytes());
            message.push(b'\n');
            env::err(&message);
            std::process::exit(1);
        }
    };
    let output_path = temporary.path().join("highlevel.json");
    let status = Command::new("streaming_extractor_music")
        .arg(audio.as_os())
        .arg(&output_path)
        .stdin(Stdio::inherit())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    match status {
        Err(error) => {
            let mut message =
                Vec::from(&b"[music-highlevel] cannot run streaming_extractor_music: "[..]);
            message.extend_from_slice(env::os_error_text(&error).as_bytes());
            message.push(b'\n');
            env::err(&message);
            std::process::exit(1);
        }
        Ok(status) if !status.success() => {
            env::err(&message_with_path(
                b"[music-highlevel] extractor failed: ",
                audio,
                b"\n",
            ));
            return None;
        }
        Ok(_) => {}
    }

    let bytes = match fs::read(&output_path) {
        Ok(bytes) => bytes,
        Err(error) => {
            let description = describe_io_error(&error, &output_path);
            let mut message = message_with_path(
                b"[music-highlevel] failed reading output for ",
                audio,
                b": ",
            );
            message.extend_from_slice(description.as_bytes());
            message.push(b'\n');
            env::err(&message);
            return None;
        }
    };
    match json::parse(&bytes) {
        Ok(value) => Some(value),
        Err(error) => {
            let mut message = message_with_path(
                b"[music-highlevel] failed reading output for ",
                audio,
                b": ",
            );
            message.extend_from_slice(error.to_string().as_bytes());
            message.push(b'\n');
            env::err(&message);
            None
        }
    }
}

// ===========================================================================
// Output
// ===========================================================================

fn emit(audio: &PyPath, highlevel: &[(String, Entry)], json_output: bool) {
    if json_output {
        let Ok(path) = String::from_utf8(audio.as_bytes().to_vec()) else {
            // orjson refuses a str carrying surrogate escapes; Python exits 1.
            env::err(b"TypeError: str is not valid UTF-8: surrogates not allowed\n");
            std::process::exit(1);
        };
        let entries = highlevel
            .iter()
            .map(|(name, entry)| (name.clone(), entry.clone().into_json()))
            .collect();
        let document = Json::Obj(vec![
            ("path".to_string(), Json::Str(path)),
            ("highlevel".to_string(), Json::Obj(entries)),
        ]);
        let mut line = json::dump(&document).into_bytes();
        line.push(b'\n');
        env::out(&line);
        return;
    }

    env::out(audio.as_bytes());
    env::out(b"\n");
    if highlevel.is_empty() {
        env::out(b"  (no highlevel data)\n");
        return;
    }
    for (name, entry) in highlevel {
        let mut line = Vec::from(&b"  "[..]);
        line.extend_from_slice(name.as_bytes());
        line.push(b':');
        if let Some(value) = &entry.value {
            line.extend_from_slice(b" value=");
            match value {
                Value::Text(text) => line.extend_from_slice(text.as_bytes()),
                Value::Number(number) => {
                    line.extend_from_slice(pyfmt::python_float_repr(*number).as_bytes())
                }
            }
        }
        if let Some(score) = entry.score {
            line.extend_from_slice(b" score=");
            line.extend_from_slice(pyfmt::python_fixed3(score).as_bytes());
        }
        line.push(b'\n');
        env::out(&line);
        if let Some(candidates) = &entry.candidates {
            for candidate in candidates {
                let mut line = Vec::from(&b"    "[..]);
                line.extend_from_slice(pyfmt::python_fixed3(candidate.score).as_bytes());
                line.push(b'\t');
                line.extend_from_slice(candidate.label.as_bytes());
                line.push(b'\n');
                env::out(&line);
            }
        }
    }
}

// ===========================================================================
// main
// ===========================================================================

fn basename(argv0: &[u8]) -> Vec<u8> {
    match argv0.iter().rposition(|byte| *byte == b'/') {
        Some(position) => argv0[position + 1..].to_vec(),
        None => argv0.to_vec(),
    }
}

fn terminal_columns() -> usize {
    if let Some(value) = env::var_bytes("COLUMNS") {
        if let Some(parsed) = parse_python_int(&value) {
            if parsed > 0 {
                return if parsed > 1_000_000 {
                    1_000_000
                } else {
                    parsed as usize
                };
            }
        }
    }
    // Python falls back to the terminal attached to stdout (80 when stdin or
    // stdout is not a tty). The port cannot ask for the size without a libc
    // call, so it uses the documented fallback.
    80
}

fn main() {
    let mut raw_args = std::env::args_os();
    let argv0: OsString = raw_args.next().unwrap_or_else(|| OsString::from(PROGRAM));
    let prog = basename(argv0.as_bytes());
    let argv: Vec<Vec<u8>> = raw_args.map(|arg| arg.as_bytes().to_vec()).collect();
    let width = terminal_columns().saturating_sub(2);

    let parsed = match parse_args(&argv, &prog, width) {
        Ok(parsed) => parsed,
        Err(message) => {
            let prog_text = String::from_utf8_lossy(&prog);
            let usage = usage_text(&prog_text, width);
            let mut out = usage.trim_end_matches('\n').as_bytes().to_vec();
            out.push(b'\n');
            out.extend_from_slice(&prog);
            out.extend_from_slice(b": error: ");
            out.extend_from_slice(&message);
            out.push(b'\n');
            env::err(&out);
            std::process::exit(2);
        }
    };

    let selection = if parsed.taxonomies.is_empty() {
        Selection::Defaults
    } else {
        Selection::Explicit(&parsed.taxonomies)
    };

    let mut inputs: Vec<PyPath> = parsed
        .paths
        .iter()
        .map(|path| PyPath::from_bytes(path).expanduser())
        .collect();
    if inputs.is_empty() {
        let current = current_track();
        if current.starts_with(b"file://") {
            if let Some(path) = file_url_path(&current) {
                if !path.is_empty() {
                    inputs = vec![PyPath::from_bytes(&path)];
                }
            }
        }
    }
    if inputs.is_empty() {
        env::err(b"[music-highlevel] no inputs provided\n");
        std::process::exit(1);
    }

    let files = walk_inputs(&inputs);
    if files.is_empty() {
        env::err(b"[music-highlevel] no audio files found\n");
        std::process::exit(1);
    }

    for audio in &files {
        let Some(data) = run_extractor(audio) else {
            continue;
        };
        if data.as_object().is_none() {
            // Python's `data.get` raises AttributeError here, aborting the run.
            env::err(&message_with_path(
                b"[music-highlevel] extractor output is not a JSON object: ",
                audio,
                b"\n",
            ));
            std::process::exit(1);
        }
        let highlevel = match data.get("highlevel") {
            Some(Json::Obj(entries)) => entries,
            _ => {
                env::err(&message_with_path(
                    b"[music-highlevel] missing highlevel section: ",
                    audio,
                    b"\n",
                ));
                continue;
            }
        };
        let extracted = extract_highlevel(highlevel, &selection, parsed.top);
        emit(audio, &extracted, parsed.json_output);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(arguments: &[&str]) -> Result<Parsed, Vec<u8>> {
        let argv: Vec<Vec<u8>> = arguments
            .iter()
            .map(|arg| arg.as_bytes().to_vec())
            .collect();
        parse_args(&argv, b"music-highlevel", 78)
    }

    fn error(arguments: &[&str]) -> String {
        String::from_utf8(parse(arguments).unwrap_err()).expect("UTF-8 error")
    }

    #[test]
    fn help_matches_argparse_at_80_columns() {
        let expected = "\
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
";
        assert_eq!(help_text("music-highlevel", 78), expected);
    }

    #[test]
    fn help_matches_argparse_at_40_columns() {
        let expected = "\
usage: music-highlevel [-h]
                       [--top TOP]
                       [--taxonomies [TAXONOMIES ...]]
                       [--json]
                       [paths ...]

Inspect Essentia highlevel classifiers
for audio files

positional arguments:
  paths           audio files or
                  directories;
                  defaults to current
                  track via playerctl

options:
  -h, --help      show this help
                  message and exit
  --top TOP       top probabilities
                  per taxonomy to
                  display
  --taxonomies [TAXONOMIES ...]
                  specific highlevel
                  taxonomies to
                  include (defaults to
                  a common subset)
  --json          emit JSON per track
";
        assert_eq!(help_text("music-highlevel", 38), expected);
    }

    #[test]
    fn usage_matches_argparse_error_prefix() {
        assert_eq!(
            usage_text("music-highlevel", 78).trim_end_matches('\n'),
            "usage: music-highlevel [-h] [--top TOP] [--taxonomies [TAXONOMIES ...]]\n                       [--json]\n                       [paths ...]"
        );
    }

    #[test]
    fn defaults_apply() {
        let parsed = parse(&[]).unwrap();
        assert_eq!(parsed.top, 3);
        assert!(parsed.taxonomies.is_empty());
        assert!(!parsed.json_output);
        assert!(parsed.paths.is_empty());
    }

    #[test]
    fn paths_and_options_mix_like_argparse() {
        // Positionals after the last option are taken when no positional run
        // was consumed earlier.
        let parsed = parse(&["--json", "--top", "5", "a.mp3", "b.mp3"]).unwrap();
        assert_eq!(parsed.paths, vec![b"a.mp3".to_vec(), b"b.mp3".to_vec()]);
        assert!(parsed.json_output);
        assert_eq!(parsed.top, 5);

        // A run that appears before an option consumes the sole positional, so
        // the later run is unrecognized (argparse's exact behaviour).
        assert_eq!(
            error(&["a.mp3", "--json", "b.mp3"]),
            "unrecognized arguments: b.mp3"
        );
        assert_eq!(
            error(&["a.mp3", "--json", "--top", "5", "b.mp3"]),
            "unrecognized arguments: b.mp3"
        );
    }

    #[test]
    fn taxonomies_star_consumes_following_values() {
        let parsed = parse(&["--taxonomies", "genre_dortmund", "moods_mirex"]).unwrap();
        assert_eq!(
            parsed.taxonomies,
            vec![b"genre_dortmund".to_vec(), b"moods_mirex".to_vec()]
        );
        assert!(parsed.paths.is_empty());
        assert!(parse(&["--taxonomies"]).unwrap().taxonomies.is_empty());
    }

    #[test]
    fn long_options_accept_equals_and_abbreviations() {
        assert_eq!(parse(&["--top=4"]).unwrap().top, 4);
        assert_eq!(parse(&["--top", "-2"]).unwrap().top, -2);
        assert!(parse(&["--j"]).unwrap().json_output);
        assert_eq!(
            error(&["--t=3"]),
            "ambiguous option: --t=3 could match --top, --taxonomies"
        );
    }

    #[test]
    fn errors_match_argparse() {
        assert_eq!(error(&["--bogus"]), "unrecognized arguments: --bogus");
        assert_eq!(
            error(&["--top", "x"]),
            "argument --top: invalid int value: 'x'"
        );
        assert_eq!(
            error(&["--top", "-x"]),
            "argument --top: expected one argument"
        );
        assert_eq!(
            error(&["--json=false"]),
            "argument --json: ignored explicit argument 'false'"
        );
        assert_eq!(
            error(&["--json="]),
            "argument --json: ignored explicit argument ''"
        );
        assert_eq!(error(&["-x"]), "unrecognized arguments: -x");
        assert_eq!(
            error(&["a", "--top", "1", "--", "b"]),
            "unrecognized arguments: -- b"
        );
    }

    #[test]
    fn double_dash_is_stripped_from_positionals() {
        let parsed = parse(&["--", "--json", "a.mp3"]).unwrap();
        assert_eq!(parsed.paths, vec![b"--json".to_vec(), b"a.mp3".to_vec()]);
        assert!(!parsed.json_output);
        assert!(parse(&["-"]).is_ok());
        assert_eq!(parse(&["-"]).unwrap().paths, vec![b"-".to_vec()]);
    }

    #[test]
    fn python_int_accepts_python_literals() {
        assert_eq!(parse_python_int(b"3"), Some(3));
        assert_eq!(parse_python_int(b" 3 "), Some(3));
        assert_eq!(parse_python_int(b"+3"), Some(3));
        assert_eq!(parse_python_int(b"-0"), Some(0));
        assert_eq!(parse_python_int(b"1_000"), Some(1000));
        assert_eq!(parse_python_int(b"-1_0"), Some(-10));
        assert_eq!(parse_python_int(b"3.0"), None);
        assert_eq!(parse_python_int(b"1_"), None);
        assert_eq!(parse_python_int(b"_1"), None);
        assert_eq!(parse_python_int(b"1__0"), None);
        assert_eq!(parse_python_int(b""), None);
        assert_eq!(parse_python_int(b"-"), None);
        assert_eq!(parse_python_int(&[b'9'; 200]).unwrap(), i128::MAX);
    }

    #[test]
    fn repr_quotes_like_python() {
        assert_eq!(python_repr(b"x"), "'x'");
        assert_eq!(python_repr(b"a'b"), "\"a'b\"");
        assert_eq!(python_repr(b"a'b\"c"), "'a\\'b\"c'");
        assert_eq!(python_repr(b"a\nb"), "'a\\nb'");
        assert_eq!(python_repr(b"\xff"), "'\\udcff'");
        assert_eq!(python_repr("é".as_bytes()), "'é'");
    }

    #[test]
    fn probabilities_sort_and_truncate() {
        let probabilities = vec![
            ("rock".to_string(), Json::Num(0.25)),
            ("pop".to_string(), Json::Num(0.5)),
            ("jazz".to_string(), Json::Num(0.25)),
        ];
        let candidates = truncate_probs(&probabilities, 3);
        assert_eq!(
            candidates,
            vec![
                Candidate {
                    label: "pop".to_string(),
                    score: 0.5
                },
                Candidate {
                    label: "rock".to_string(),
                    score: 0.25
                },
                Candidate {
                    label: "jazz".to_string(),
                    score: 0.25
                },
            ]
        );
        assert_eq!(truncate_probs(&probabilities, 1).len(), 1);
        assert_eq!(truncate_probs(&probabilities, 0).len(), 3);
        assert_eq!(truncate_probs(&probabilities, -1).len(), 3);

        let broken = vec![
            ("bad".to_string(), Json::Null),
            ("good".to_string(), Json::Num(0.5)),
        ];
        assert!(truncate_probs(&broken, 3).is_empty());
    }

    #[test]
    fn extraction_keeps_python_shapes() {
        let highlevel = vec![
            (
                "genre_dortmund".to_string(),
                Json::Obj(vec![
                    (
                        "probability".to_string(),
                        Json::Obj(vec![
                            ("rock".to_string(), Json::Num(0.5)),
                            ("pop".to_string(), Json::Num(0.5)),
                        ]),
                    ),
                    ("value".to_string(), Json::Str("rock".to_string())),
                ]),
            ),
            (
                "danceability".to_string(),
                Json::Obj(vec![
                    ("probability".to_string(), Json::Num(0.75)),
                    ("value".to_string(), Json::Num(1.0)),
                ]),
            ),
            (
                "skipped".to_string(),
                Json::Obj(vec![(
                    "probability".to_string(),
                    Json::Obj(vec![("x".to_string(), Json::Num(1.0))]),
                )]),
            ),
            (
                "ignored".to_string(),
                Json::Str("not an object".to_string()),
            ),
        ];
        let extracted = extract_highlevel(&highlevel, &Selection::Defaults, 3);
        let names: Vec<&str> = extracted.iter().map(|(name, _)| name.as_str()).collect();
        assert_eq!(names, vec!["genre_dortmund", "danceability"]);
        let genre = &extracted[0].1;
        assert_eq!(
            genre.candidates.as_ref().unwrap()[0],
            Candidate {
                label: "rock".to_string(),
                score: 0.5
            }
        );
        assert_eq!(genre.value, Some(Value::Text("rock".to_string())));
        assert_eq!(extracted[1].1.score, Some(0.75));
        assert_eq!(extracted[1].1.value, Some(Value::Number(1.0)));
    }

    #[test]
    fn file_urls_are_decoded() {
        assert_eq!(
            file_url_path(b"file:///tmp/a%20b.mp3").unwrap(),
            b"/tmp/a b.mp3"
        );
        assert_eq!(
            file_url_path(b"file://host/tmp/x.mp3?q=1#f").unwrap(),
            b"/tmp/x.mp3"
        );
        assert_eq!(file_url_path(b"file://").unwrap(), b"");
        assert_eq!(file_url_path(b"file://host").unwrap(), b"");
    }
}
