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
use std::process::ExitCode;

use pleamar_theme::themes;
use pleamar_theme::time;

const TOOL: &str = "pleamar-themes";

const USAGE: &str = "\
pleamar-themes — themes as files for ~/.config/pleamar/theme.plm

  pleamar-themes list                 themes in $XDG_CONFIG_HOME/pleamar/themes
  pleamar-themes apply FILE|NAME      write theme.plm from that theme
  pleamar-themes show FILE|NAME       print the theme.plm it would write
  pleamar-themes -h | --help

A bare NAME reads <config>/pleamar/themes/<NAME>.toml; a value with a slash is
a path. `apply` replaces <config>/pleamar/theme.plm atomically, which is the
file a running scene imports — it re-themes on its next reload.

A theme file is a small TOML subset; every key is optional (the stock palette
fills what is missing):

  name   = \"Retro\"        # shown by `list`
  font   = \"Iosevka\"      # shown by `list`, not written into theme.plm
  corner_rounding = 18   # likewise: the compositor's setting
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

fn write_theme(args: &[String], write: bool) -> ExitCode {
    let Some(target) = args.first() else {
        return usage_fail("apply/show needs a theme file or a name");
    };
    let directory = match themes_dir() {
        Ok(directory) => directory,
        Err(error) => return fail(error),
    };
    let path = resolve(target, &directory);
    let theme_file = match read_theme(&path) {
        Ok(theme_file) => theme_file,
        Err(error) => return fail(format!("{}: {error}", path.display())),
    };
    let contents = theme_file
        .to_theme(&path)
        .render(&time::utc_timestamp_now());
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

    let mut rows: Vec<(String, String, String, String)> = Vec::new();
    let mut failed = false;
    for path in files {
        let name = stem(&path).to_string();
        match read_theme(&path) {
            Ok(theme) => rows.push((
                theme.name.unwrap_or(name),
                theme.font.unwrap_or_else(|| "-".to_string()),
                theme
                    .corner_rounding
                    .map(|value| value.to_string())
                    .unwrap_or_else(|| "-".to_string()),
                path.display().to_string(),
            )),
            Err(error) => {
                err(format!("{}: {error}", path.display()));
                failed = true;
            }
        }
    }

    if rows.is_empty() {
        if !failed && !plain {
            println!("{TOOL}: no themes in {}", directory.display());
        }
        return if failed {
            ExitCode::from(1)
        } else {
            ExitCode::SUCCESS
        };
    }
    if plain {
        // One line per theme, for the scene's logic: name, font, corners, the
        // file, and 1 when it is the theme `theme.plm` was made from.
        let applied = applied_source();
        for row in &rows {
            let selected = applied
                .as_deref()
                .is_some_and(|source| same_file(source, &row.3));
            println!(
                "{}\t{}\t{}\t{}\t{}",
                row.0,
                row.1,
                row.2,
                row.3,
                if selected { "1" } else { "0" }
            );
        }
        return if failed {
            ExitCode::from(1)
        } else {
            ExitCode::SUCCESS
        };
    }
    let name_width = rows
        .iter()
        .map(|row| row.0.chars().count())
        .chain(std::iter::once("NAME".len()))
        .max()
        .unwrap_or(4);
    let font_width = rows
        .iter()
        .map(|row| row.1.chars().count())
        .chain(std::iter::once("FONT".len()))
        .max()
        .unwrap_or(4);
    println!(
        "{:<name_width$}  {:<font_width$}  {:>7}  {}",
        "NAME", "FONT", "CORNERS", "FILE"
    );
    for row in &rows {
        println!(
            "{:<name_width$}  {:<font_width$}  {:>7}  {}",
            row.0, row.1, row.2, row.3
        );
    }
    if failed {
        ExitCode::from(1)
    } else {
        ExitCode::SUCCESS
    }
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
