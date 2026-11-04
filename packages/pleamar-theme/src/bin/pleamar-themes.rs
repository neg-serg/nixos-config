//! `pleamar-themes` — themes as files for `~/.config/pleamar/theme.plm`.
//!
//! `pleamar-theme` derives the palette from the wallpaper; this reads a
//! hand-written palette instead and writes the same `library Skin` the
//! pipeline writes, so a running scene re-themes on the reload it already does
//! for any change of `theme.plm`.
//!
//!   pleamar-themes list                 themes in $XDG_CONFIG_HOME/pleamar/themes
//!   pleamar-themes apply FILE|NAME      write theme.plm from that theme
//!   pleamar-themes show FILE|NAME       print the theme.plm it would write
//!
//! A bare NAME is `<config>/pleamar/themes/<NAME>.toml`; anything with a slash
//! is a path. Nothing here samples a wallpaper, and nothing else under
//! `~/.config/pleamar` is touched.

use std::env;
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{ExitCode, Stdio};

use pleamar_theme::render;
use pleamar_theme::themes;
use pleamar_theme::time;

const TOOL: &str = "pleamar-themes";

const USAGE: &str = "\
pleamar-themes — themes as files for ~/.config/pleamar/theme.plm

  pleamar-themes list                 themes in $XDG_CONFIG_HOME/pleamar/themes
  pleamar-themes apply FILE|NAME      write theme.plm from that theme
  pleamar-themes show FILE|NAME       print the theme.plm it would write
  pleamar-themes push                 hand the palette to the scenes that draw it
  pleamar-themes warm KELVIN          the light theme's paper: 2700 warm, 6500 neutral
  pleamar-themes -h | --help

A bare NAME reads <config>/pleamar/themes/<NAME>.toml; a value with a slash is
a path. `apply` replaces <config>/pleamar/theme.plm atomically, which is the
file a running scene imports — it re-themes on its next reload.

A light theme (`light = true`) names its accent and nothing else about the
whites: its paper, the surface under it and the ink are worked out from the
warmth in KELVIN (`warm`, default 4300), so the whole light side follows one
number. A dark theme keeps the colours its file gives.

A theme file is a small TOML subset; every key is optional (the stock palette
fills what is missing):

  name   = \"Retro\"        # shown by `list`
  light  = false         # skin.light and the header's mode

  [palette]
  coal    = \"#101418\"     # colors.background
  surface = \"#242A35\"     # colors.surfaceVariant
  ink     = \"#CBD6E5\"     # colors.text.primary
  ink_dim = \"#AEB9C8\"     # colors.text.secondary
  accent  = \"#006FCC\"     # colors.accent.primary

Exit: 0 done, 1 a theme or a file could not be read/parsed, 2 usage.
";

fn main() -> ExitCode {
    run()
}

fn run() -> ExitCode {
    let args: Vec<String> = env::args_os()
        .skip(1)
        .map(|argument| argument.to_string_lossy().into_owned())
        .collect();
    let Some(command) = args.first() else {
        return usage_fail("no command");
    };
    match command.as_str() {
        "-h" | "--help" => {
            print!("{USAGE}");
            ExitCode::SUCCESS
        }
        "list" => list(&args[1..]),
        "apply" => write_theme(&args[1..], true),
        "show" => write_theme(&args[1..], false),
        "push" => push(),
        "warm" => warm(&args[1..]),
        other => usage_fail(format!("unknown command '{other}'")),
    }
}

fn err(message: impl std::fmt::Display) {
    eprintln!("{TOOL}: {message}");
}

fn fail(message: impl std::fmt::Display) -> ExitCode {
    err(message);
    ExitCode::from(1)
}

fn usage_fail(message: impl std::fmt::Display) -> ExitCode {
    err(message);
    err("see --help");
    ExitCode::from(2)
}

fn config_home() -> Result<PathBuf, String> {
    if let Some(value) = env::var_os("XDG_CONFIG_HOME") {
        if !value.is_empty() {
            return Ok(PathBuf::from(value));
        }
    }
    match env::var_os("HOME") {
        Some(value) if !value.is_empty() => Ok(PathBuf::from(value).join(".config")),
        _ => Err("HOME is not set — nothing to read or write".to_string()),
    }
}

fn themes_dir() -> Result<PathBuf, String> {
    Ok(config_home()?.join("pleamar/themes"))
}

fn output_file() -> Result<PathBuf, String> {
    Ok(config_home()?.join("pleamar/theme.plm"))
}

/// A bare name is a file in the themes directory; a value with a slash is a
/// path, as given.
fn resolve(target: &str, directory: &Path) -> PathBuf {
    if target.contains('/') {
        return PathBuf::from(target);
    }
    if target.ends_with(".toml") {
        directory.join(target)
    } else {
        directory.join(format!("{target}.toml"))
    }
}

fn read_theme(path: &Path) -> Result<themes::ThemeFile, String> {
    let text = fs::read_to_string(path)
        .map_err(|error| format!("cannot read {}: {error}", path.display()))?;
    themes::parse(&text)
}

/// The warmth a light theme's paper is worked out at: a plain number in
/// `$XDG_CONFIG_HOME/pleamar/warmth`, so the drawer and the tool agree without
/// either reading the other's state.
fn warmth_path() -> Result<PathBuf, String> {
    Ok(config_home()?.join("pleamar/warmth"))
}

fn read_warmth() -> f64 {
    let Ok(path) = warmth_path() else {
        return themes::WARMTH_DEFAULT;
    };
    let Ok(text) = fs::read_to_string(path) else {
        return themes::WARMTH_DEFAULT;
    };
    text.trim()
        .parse::<f64>()
        .map(|kelvin| kelvin.clamp(themes::WARMTH_MIN, themes::WARMTH_MAX))
        .unwrap_or(themes::WARMTH_DEFAULT)
}

fn write_warmth(kelvin: f64) -> Result<(), String> {
    let path = warmth_path()?;
    if let Some(directory) = path.parent() {
        fs::create_dir_all(directory)
            .map_err(|error| format!("cannot create {}: {error}", directory.display()))?;
    }
    write_atomic(&path, &format!("{kelvin:.0}\n"))
        .map_err(|error| format!("cannot write {}: {error}", path.display()))
}

/// Read a theme file and render it. A light theme's whites come from the stored
/// warmth (`warm_palette`); a dark one keeps the file's colours.
fn build_theme(path: &Path) -> Result<(themes::ThemeFile, render::Theme), String> {
    let theme_file = read_theme(path)?;
    let theme = if theme_file.light {
        let kelvin = read_warmth();
        let palette = themes::warm_palette(kelvin, &theme_file.accent);
        theme_file.to_theme_at(path, &palette, kelvin)
    } else {
        theme_file.to_theme(path)
    };
    Ok((theme_file, theme))
}

fn write_theme(args: &[String], write: bool) -> ExitCode {
    let Some(target) = args.first() else {
        return usage_fail("apply/show needs a theme file or a name");
    };
    let directory = match themes_dir() {
        Ok(directory) => directory,
        Err(error) => return fail(error),
    };
    let path = resolve(target, &directory);
    let (theme_file, theme) = match build_theme(&path) {
        Ok(built) => built,
        Err(error) => return fail(format!("{}: {error}", path.display())),
    };
    let contents = theme.render(&time::utc_timestamp_now());
    if !write {
        print!("{contents}");
        return ExitCode::SUCCESS;
    }
    let output = match output_file() {
        Ok(output) => output,
        Err(error) => return fail(error),
    };
    if let Err(error) = write_atomic(&output, &contents) {
        return fail(format!("cannot write {}: {error}", output.display()));
    }
    println!("{TOOL}: wrote {}", output.display());
    let name = theme_file
        .name
        .clone()
        .unwrap_or_else(|| stem(&path).to_string());
    println!("{TOOL}: theme {name}");
    // The converted scenes read their own `palette.json`; a theme still applies
    // when that hand-off fails, and the failure is said rather than hidden.
    if let Err(error) = push_palette() {
        eprintln!("{TOOL}: warning: {error}");
    }
    ExitCode::SUCCESS
}

/// The source line of the `theme.plm` in place, if it names one.
fn applied_source() -> Option<String> {
    let text = fs::read_to_string(output_file().ok()?).ok()?;
    text.lines().find_map(|line| {
        line.strip_prefix("// source:")
            .map(|rest| rest.trim().to_string())
    })
}

/// Whether two path spellings name the same file (a theme applied by a relative
/// path still matches the directory entry `list` found).
fn same_file(left: &str, right: &str) -> bool {
    if left == right {
        return true;
    }
    match (fs::canonicalize(left), fs::canonicalize(right)) {
        (Ok(left), Ok(right)) => left == right,
        _ => false,
    }
}

/// The scenes that draw with `lib/palette-live.plm`, by scene name (the folder
/// under `~/.local/share/pleamar/` they read their own files from).
const PALETTE_SCENES: [&str; 9] = [
    "bar",
    "panels",
    "launcher",
    "notifications",
    "toast",
    "picker",
    "widgets",
    "osd",
    "headphones",
];

fn data_home() -> Result<PathBuf, String> {
    if let Some(value) = env::var_os("XDG_DATA_HOME") {
        if !value.is_empty() {
            return Ok(PathBuf::from(value));
        }
    }
    match env::var_os("HOME") {
        Some(value) if !value.is_empty() => Ok(PathBuf::from(value).join(".local/share")),
        _ => Err("HOME is not set — nothing to write".to_string()),
    }
}

/// Write the palette into each converted scene's data folder, where its logic
/// reads it (`files.read` never leaves the scene's own directory).
fn push_palette() -> Result<usize, String> {
    let output = output_file()?;
    let mut palette = themes::palette_from_theme_file(&output)?;
    palette.temperature = Some(read_warmth());
    let data = data_home()?;
    let json = palette.json();
    let mut written = 0;
    for scene in PALETTE_SCENES {
        let directory = data.join("pleamar").join(scene);
        fs::create_dir_all(&directory)
            .map_err(|error| format!("cannot create {}: {error}", directory.display()))?;
        let _ = fs::set_permissions(&directory, fs::Permissions::from_mode(0o700));
        write_atomic(&directory.join("palette.json"), &json)
            .map_err(|error| format!("cannot write the palette for {scene}: {error}"))?;
        // The scene polls that file every two seconds; one `--say` makes a theme
        // change (and the warmth slider) visible at once. A scene that is not
        // running refuses and is ignored.
        let mut facts: Vec<String> = Vec::new();
        for (name, channels) in [
            ("coal", palette.coal),
            ("surface", palette.surface),
            ("ink", palette.ink),
            ("ink_dim", palette.ink_dim),
            ("accent", palette.accent),
            ("on_accent", palette.on_accent),
        ] {
            for (channel, value) in [("r", channels.0), ("g", channels.1), ("b", channels.2)] {
                facts.push(format!("fact pal_{name}_{channel} {value:.4}"));
            }
        }
        facts.push(format!(
            "fact pal_light {}",
            if palette.light { 1 } else { 0 }
        ));
        let _ = std::process::Command::new("pleamar")
            .arg("--say")
            .arg(scene)
            .args(&facts)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
        written += 1;
    }
    Ok(written)
}

fn push() -> ExitCode {
    match push_palette() {
        Ok(written) => {
            println!("{TOOL}: pushed the palette to {written} scene(s)");
            ExitCode::SUCCESS
        }
        Err(error) => fail(error),
    }
}

/// One theme as `list` shows it and `--plain` hands to the scene's logic.
struct Row {
    name: String,
    light: bool,
    path: String,
    selected: bool,
    accent: (f64, f64, f64),
}

/// `warm KELVIN`: store the light theme's warmth and, when a light theme is the
/// one in place, rebuild `theme.plm` from it — which re-renders the lock screen
/// and pushes the palette to the scenes in one go.
fn warm(args: &[String]) -> ExitCode {
    let Some(value) = args.first() else {
        return usage_fail("warm needs a temperature in kelvin (2700 warm, 6500 neutral)");
    };
    let kelvin = match value.parse::<f64>() {
        Ok(kelvin) if (2000.0..=8000.0).contains(&kelvin) => kelvin,
        _ => return fail(format!("warmth is 2000..8000 K, not '{value}'")),
    };
    let kelvin = kelvin.clamp(themes::WARMTH_MIN, themes::WARMTH_MAX);
    if let Err(error) = write_warmth(kelvin) {
        return fail(error);
    }
    let applied = applied_source();
    let rebuilt = applied
        .as_deref()
        .filter(|source| source.ends_with(".toml"))
        .map(Path::new)
        .filter(|path| path.is_file())
        .and_then(|path| match build_theme(path) {
            Ok((theme_file, theme)) if theme_file.light => {
                Some((path.to_path_buf(), theme_file, theme))
            }
            _ => None,
        });
    let Some((path, theme_file, theme)) = rebuilt else {
        println!("{TOOL}: warmth {kelvin:.0} K stored; the theme in place is not a light one");
        return ExitCode::SUCCESS;
    };
    let output = match output_file() {
        Ok(output) => output,
        Err(error) => return fail(error),
    };
    let contents = theme.render(&time::utc_timestamp_now());
    if let Err(error) = write_atomic(&output, &contents) {
        return fail(format!("cannot write {}: {error}", output.display()));
    }
    let name = theme_file.name.unwrap_or_else(|| stem(&path).to_string());
    println!(
        "{TOOL}: {name} at {kelvin:.0} K, wrote {}",
        output.display()
    );
    if let Err(error) = push_palette() {
        eprintln!("{TOOL}: warning: {error}");
    }
    ExitCode::SUCCESS
}

fn list(args: &[String]) -> ExitCode {
    let plain = args.iter().any(|argument| argument == "--plain");
    let directory = match themes_dir() {
        Ok(directory) => directory,
        Err(error) => return fail(error),
    };
    if !directory.is_dir() {
        return fail(format!(
            "no themes directory at {} (create it and put a .toml there)",
            directory.display()
        ));
    }
    let mut files: Vec<PathBuf> = match fs::read_dir(&directory) {
        Ok(entries) => entries
            .filter_map(Result::ok)
            .map(|entry| entry.path())
            .filter(|path| {
                path.extension()
                    .is_some_and(|extension| extension == "toml")
            })
            .collect(),
        Err(error) => return fail(format!("cannot read {}: {error}", directory.display())),
    };
    files.sort();

    let applied = applied_source();
    let mut rows: Vec<Row> = Vec::new();
    let mut failed = false;
    for path in files {
        let name = stem(&path).to_string();
        match read_theme(&path) {
            Ok(theme) => {
                let shown = path.display().to_string();
                rows.push(Row {
                    name: theme.name.unwrap_or(name),
                    light: theme.light,
                    selected: applied
                        .as_deref()
                        .is_some_and(|source| same_file(source, &shown)),
                    path: shown,
                    accent: themes::channels(&theme.accent).unwrap_or((0.0, 0.0, 0.0)),
                })
            }
            Err(error) => {
                err(format!("{}: {error}", path.display()));
                failed = true;
            }
        }
    }

    let failed_code = if failed {
        ExitCode::from(1)
    } else {
        ExitCode::SUCCESS
    };
    if rows.is_empty() {
        if !failed && !plain {
            println!("{TOOL}: no themes in {}", directory.display());
        }
        return failed_code;
    }
    if plain {
        // One line per theme, for the scene's logic: name, the file, 1 when it is
        // the theme `theme.plm` was made from, the accent as three `rgb()` channels
        // (so a row draws its own swatch), and 1 for a light theme.
        for row in &rows {
            let (red, green, blue) = row.accent;
            println!(
                "{}\t{}\t{}\t{red:.4}\t{green:.4}\t{blue:.4}\t{}",
                row.name,
                row.path,
                if row.selected { "1" } else { "0" },
                if row.light { "1" } else { "0" }
            );
        }
        return failed_code;
    }
    let name_width = rows
        .iter()
        .map(|row| row.name.chars().count())
        .chain(std::iter::once("NAME".len()))
        .max()
        .unwrap_or(4);
    println!("{:<name_width$}  {:<5}  {}", "NAME", "LIGHT", "FILE");
    for row in &rows {
        println!(
            "{:<name_width$}  {:<5}  {}",
            row.name,
            if row.light { "yes" } else { "no" },
            row.path
        );
    }
    failed_code
}

fn stem(path: &Path) -> &str {
    path.file_stem()
        .and_then(|stem| stem.to_str())
        .unwrap_or("theme")
}

/// Write through a temp file in the destination directory, then rename: a
/// scene never reads half a file.
fn write_atomic(path: &Path, contents: &str) -> io::Result<()> {
    let directory = match path.parent() {
        Some(parent) if !parent.as_os_str().is_empty() => parent.to_path_buf(),
        _ => PathBuf::from("."),
    };
    fs::create_dir_all(&directory)?;
    let mut temp = None;
    for attempt in 0..100 {
        let candidate = directory.join(format!(".theme.plm.{}.{attempt}", std::process::id()));
        match OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&candidate)
        {
            Ok(file) => {
                temp = Some((candidate, file));
                break;
            }
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error),
        }
    }
    let Some((temp_path, mut file)) = temp else {
        return Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            "no unique temp name after 100 attempts",
        ));
    };
    // 0644, like the pipeline's writer: the file is the shell's, not a secret.
    let result = file
        .write_all(contents.as_bytes())
        .and_then(|()| file.sync_all())
        .and_then(|()| fs::set_permissions(&temp_path, fs::Permissions::from_mode(0o644)))
        .and_then(|()| fs::rename(&temp_path, path));
    if result.is_err() {
        let _ = fs::remove_file(&temp_path);
    }
    result
}
