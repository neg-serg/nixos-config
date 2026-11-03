//! `pleamar-theme` — the pleamar theme pipeline.
//!
//! A behaviour-preserving port of `files/pleamar/scripts/theme/theme.sh` plus
//! `theme-extract.awk`: resolve the wallpaper (option, canonical cache, legacy
//! cache), sample it through ImageMagick and the ported Oklab sampler, apply
//! `--from-json`/`--accent`/`--mode`, and rewrite
//! `~/.config/pleamar/theme.plm` atomically. The CLI, every diagnostic and the
//! generated file are the shell's, byte for byte.

#![forbid(unsafe_code)]

mod cli;
mod tools;

use std::ffi::{OsStr, OsString};
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::os::unix::ffi::OsStringExt;
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use pleamar_theme::extract::{self, Palette};
use pleamar_theme::hex;
use pleamar_theme::render::Theme;
use pleamar_theme::time;

const TOOL: &str = "theme";

fn main() -> ExitCode {
    run()
}

/// `err` in the shell: `theme: <message>` on stderr.
fn err(message: impl std::fmt::Display) {
    eprintln!("{TOOL}: {message}");
}

/// `die`: exit 1.
fn fail(message: impl std::fmt::Display) -> ExitCode {
    err(message);
    ExitCode::from(1)
}

/// `usage_die`: message plus `see --help`, exit 2.
fn usage_fail(message: impl std::fmt::Display) -> ExitCode {
    err(message);
    err("see --help");
    ExitCode::from(2)
}

/// `tool_die`: message only, exit 2.
fn tool_fail(message: impl std::fmt::Display) -> ExitCode {
    err(message);
    ExitCode::from(2)
}

fn run() -> ExitCode {
    // The shell checked HOME before it parsed anything, so --help also needs it.
    let home = match std::env::var_os("HOME") {
        Some(value) if !value.is_empty() => value,
        _ => {
            err("HOME is not set — nothing to write");
            return ExitCode::from(1);
        }
    };
    // Paths are built by string concatenation, not `Path::join`: the shell's
    // messages and its `// mode:` note carry the caller's spelling, and a
    // trailing slash in HOME/XDG must not disappear from them.
    let config_home = PathBuf::from(
        nonempty_env_os("XDG_CONFIG_HOME").unwrap_or_else(|| append_suffix(&home, "/.config")),
    );
    let cache_home = PathBuf::from(
        nonempty_env_os("XDG_CACHE_HOME").unwrap_or_else(|| append_suffix(&home, "/.cache")),
    );
    let output_file = PathBuf::from(append_suffix(config_home.as_os_str(), "/pleamar/theme.plm"));

    let options = match cli::parse(std::env::args_os().skip(1)) {
        cli::ParseResult::Run(options) => options,
        cli::ParseResult::Help => {
            print!("{}", cli::USAGE);
            return ExitCode::SUCCESS;
        }
        cli::ParseResult::UsageError(message) => return usage_fail(message),
    };

    // ---- resolve the wallpaper ---------------------------------------------
    let mut wallpaper: Option<PathBuf> = None;
    if !options.wallpaper.is_empty() {
        let explicit = PathBuf::from(&options.wallpaper);
        if !tools::readable(&explicit) {
            return fail(format!(
                "--wallpaper: not a readable file: {}",
                explicit.display()
            ));
        }
        wallpaper = Some(explicit);
    } else {
        // The one producer path (INTERFACES.md §1.2). It used to fall back to a
        // `quickshell-wallpaper-path` beside it, from the shell this pipeline
        // replaced; that shell was deleted on 2026-11-02 and nothing writes the old
        // file any more (the picker's write and `wl-greeter-sync` went on 2026-11-03),
        // so a fallback would only ever read a stale leftover.
        let cache_file = PathBuf::from(append_suffix(
            cache_home.as_os_str(),
            "/pleamar/wallpaper-path",
        ));
        if let Some(found) = read_path_file(&cache_file) {
            wallpaper = Some(PathBuf::from(found));
        }
    }

    // ---- extract, then let explicit colours win ----------------------------
    let mut extracted = false;
    let mut accent = String::new();
    let mut light_wallpaper = false;

    if let Some(wall) = &wallpaper {
        if tools::readable(wall) {
            if let Some(palette) = extract_palette(wall) {
                // Only the accent and the luminance verdict survive: the image's
                // four tones are the greeter's palette, and the shell's own
                // tones are overwritten from the theme below either way.
                extracted = true;
                accent = palette.accent.hex();
                light_wallpaper = palette.light;
            } else {
                err(format!(
                    "cannot sample '{}' (not a readable image?) — ignoring it",
                    wall.display()
                ));
            }
        } else {
            err(format!(
                "wallpaper from the cache is gone: {}",
                wall.display()
            ));
        }
    }

    // The shell's tones are the theme's own; only the accent is the wallpaper's.
    let (mut coal_note, mut surface_note, mut ink_note, mut accent_note) = if extracted {
        (
            "colors.background (Settings/colors.jsonc): the shell's tones are the theme's own."
                .to_string(),
            "colors.surfaceVariant (Settings/colors.jsonc).".to_string(),
            "colors.text.primary (Settings/colors.jsonc) — not the image's lightest cluster."
                .to_string(),
            "colors.accent.primary role: the wallpaper's mean saturated colour, hue-matched onto #006FCC (Settings/Theme.qml accentPrimary).".to_string(),
        )
    } else {
        (
            "colors.background, the QS fallback #ff000000 (opaque part): no wallpaper was sampled."
                .to_string(),
            "colors.surfaceVariant, the QS fallback #242A35: no wallpaper was sampled.".to_string(),
            "colors.text.primary, the QS fallback #CBD6E5: no wallpaper was sampled.".to_string(),
            "colors.accent.primary, the QS fallback #006FCC: no wallpaper was sampled.".to_string(),
        )
    };

    if !extracted && options.accent.is_empty() && options.from_json.is_empty() {
        err("nothing to extract: no wallpaper found and no --accent/--from-json colour");
        err(format!(
            "looked at: {}/pleamar/wallpaper-path",
            cache_home.display()
        ));
        err("pass --wallpaper FILE, --accent '#RRGGBB' or --from-json FILE");
        return ExitCode::from(1);
    }

    // ---- light or dark -----------------------------------------------------
    let mode_file = PathBuf::from(append_suffix(
        config_home.as_os_str(),
        "/pleamar/theme.mode",
    ));
    let mode_file_readable = tools::readable(&mode_file);
    let mut mode = options.mode.clone();
    if mode.is_empty() && mode_file_readable {
        match fs::read(&mode_file) {
            Ok(bytes) => mode = strip_posix_space(&bytes),
            Err(error) => {
                return fail(format!("cannot read {}: {error}", mode_file.display()));
            }
        }
    }
    if mode.is_empty() {
        mode = "auto".to_string();
    }
    let mode_from = if options.mode.is_empty() && mode_file_readable {
        mode_file.display().to_string()
    } else {
        "--mode".to_string()
    };
    let (theme, mode_note) = match mode.as_str() {
        "auto" => {
            if light_wallpaper {
                ("light", "auto: the wallpaper is light".to_string())
            } else {
                ("dark", "auto: the wallpaper is dark".to_string())
            }
        }
        "light" => ("light", format!("forced light by {mode_from}")),
        "dark" => ("dark", format!("forced dark by {mode_from}")),
        other => return usage_fail(format!("--mode: expected auto, light or dark: {other}")),
    };

    // The two palettes: the reference's own dark roles, and the same roles
    // turned round in the light theme.
    let (mut coal, mut surface, mut ink, ink_dim) = if theme == "light" {
        (
            "#F6F3F8".to_string(),
            "#E6E2EB".to_string(),
            "#1B2127".to_string(),
            "#4B5464".to_string(),
        )
    } else {
        (
            "#000000".to_string(),
            "#242A35".to_string(),
            "#CBD6E5".to_string(),
            "#AEB9C8".to_string(),
        )
    };

    // ---- --from-json -------------------------------------------------------
    if !options.from_json.is_empty() {
        let from_json = PathBuf::from(&options.from_json);
        if !tools::readable(&from_json) {
            return fail(format!("--from-json: cannot read {}", from_json.display()));
        }
        let jq = tools::env_bin("JQ_BIN", "jq");
        if tools::which(&jq).is_none() {
            return tool_fail(format!(
                "no '{jq}' on PATH (JQ_BIN overrides it); jq is needed for --from-json"
            ));
        }
        let mut json_keys = 0;
        for key in ["coal", "surface", "ink", "accent"] {
            let raw = tools::jq_string(&jq, key, &from_json).unwrap_or_default();
            let raw = trim_trailing_newlines(&raw);
            if raw.is_empty() {
                continue;
            }
            let value = String::from_utf8_lossy(raw).into_owned();
            let Some(normalized) = hex::normalize(&value) else {
                return fail(format!(
                    "--from-json: {key} is not a '#RRGGBB' colour: {value}"
                ));
            };
            let note = format!(
                "--from-json {} (overrides the sampled tone).",
                from_json.display()
            );
            match key {
                "coal" => {
                    coal = normalized;
                    coal_note = note;
                }
                "surface" => {
                    surface = normalized;
                    surface_note = note;
                }
                "ink" => {
                    ink = normalized;
                    ink_note = note;
                }
                "accent" => {
                    accent = normalized;
                    accent_note = format!(
                        "--from-json {} (overrides the sampled accent).",
                        from_json.display()
                    );
                }
                _ => unreachable!("the loop's key list is fixed"),
            }
            json_keys += 1;
        }
        if json_keys == 0 {
            return fail(format!(
                "--from-json: no coal/surface/ink/accent string in {}",
                from_json.display()
            ));
        }
    }

    // ---- --accent ----------------------------------------------------------
    if !options.accent.is_empty() {
        let Some(normalized) = hex::normalize(&options.accent) else {
            return fail(format!(
                "--accent: not a '#RRGGBB' colour: {}",
                options.accent
            ));
        };
        accent = normalized;
        accent_note = if extracted {
            "--accent (overrides the sampled accent).".to_string()
        } else {
            "--accent (no wallpaper was sampled).".to_string()
        };
    }

    // ---- fallbacks for tones an explicit colour did not name ----------------
    if coal.is_empty() {
        coal = "#000000".to_string();
    }
    if surface.is_empty() {
        surface = "#242A35".to_string();
    }
    if ink.is_empty() {
        ink = "#CBD6E5".to_string();
    }
    if accent.is_empty() {
        accent = "#006FCC".to_string();
    }

    // ---- write -------------------------------------------------------------
    let resolved = Theme {
        title: "wallpaper palette".to_string(),
        generated_by: "files/pleamar/scripts/theme/theme.sh".to_string(),
        source: wallpaper.as_ref().map(|path| path.display().to_string()),
        mode: theme,
        mode_note,
        coal_note,
        surface_note,
        ink_note,
        accent_note,
        coal,
        surface,
        ink,
        ink_dim,
        accent,
        light: theme == "light",
    };
    write_theme(&output_file, &resolved, wallpaper.as_deref())
}

/// The shell's `extract_palette`: tool check, ImageMagick, then the ported
/// awk program. Returns `None` on any failure; the caller prints the
/// "cannot sample" line, as the shell did after the command substitution.
fn extract_palette(wallpaper: &Path) -> Option<Palette> {
    let magick = tools::env_bin("MAGICK_BIN", "magick");
    if tools::which(&magick).is_none() {
        // The shell's tool_die ran in the command substitution's subshell, so
        // this message did not end the script; the caller's warning follows.
        err(format!("no '{magick}' on PATH (MAGICK_BIN overrides it)"));
        return None;
    }
    let (stdout, succeeded) = tools::magick_dump(&magick, wallpaper)?;
    let dump = String::from_utf8_lossy(&stdout);
    match extract::palette_from_dump(&dump) {
        Ok(palette) if succeeded => Some(palette),
        Ok(_) => None,
        Err(_) => {
            eprintln!("theme-extract: no pixels (is the input an ImageMagick txt: dump?)");
            None
        }
    }
}

/// The first non-empty line of a cache file, trimmed of `[[:space:]]` at both
/// ends (spaces inside a path stay). `None` when the file is absent, not a
/// regular file, unreadable, or its first line is empty.
fn read_path_file(file: &Path) -> Option<OsString> {
    if !fs::metadata(file)
        .map(|metadata| metadata.is_file())
        .unwrap_or(false)
    {
        return None;
    }
    let bytes = fs::read(file).ok()?;
    let line_end = bytes
        .iter()
        .position(|&byte| byte == b'\n')
        .unwrap_or(bytes.len());
    let line = &bytes[..line_end];
    let trimmed = trim_posix_space(line);
    if trimmed.is_empty() {
        return None;
    }
    Some(OsString::from_vec(trimmed.to_vec()))
}

fn trim_posix_space(bytes: &[u8]) -> &[u8] {
    let is_space = |byte: &u8| matches!(*byte, b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c);
    let start = bytes
        .iter()
        .position(|byte| !is_space(byte))
        .unwrap_or(bytes.len());
    let end = bytes
        .iter()
        .rposition(|byte| !is_space(byte))
        .map_or(start, |index| index + 1);
    &bytes[start..end]
}

/// `tr -d '[:space:]'`: drop every POSIX whitespace byte anywhere.
fn strip_posix_space(bytes: &[u8]) -> String {
    let filtered: Vec<u8> = bytes
        .iter()
        .copied()
        .filter(|byte| !matches!(*byte, b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c))
        .collect();
    String::from_utf8_lossy(&filtered).into_owned()
}

/// The shell's `$(...)`: strip every trailing newline.
fn trim_trailing_newlines(bytes: &[u8]) -> &[u8] {
    let mut end = bytes.len();
    while end > 0 && bytes[end - 1] == b'\n' {
        end -= 1;
    }
    &bytes[..end]
}

fn nonempty_env_os(variable: &str) -> Option<OsString> {
    match std::env::var_os(variable) {
        Some(value) if !value.is_empty() => Some(value),
        _ => None,
    }
}

/// The shell's `"$base$suffix"`: append the suffix byte for byte, so a
/// trailing slash stays doubled exactly where the shell printed it.
fn append_suffix(base: &OsStr, suffix: &str) -> OsString {
    let mut value = base.to_os_string();
    value.push(suffix);
    value
}

/// Write atomically: render into a temp file in the destination directory,
/// compare without the timestamp/source lines, then rename. The temp file is
/// removed on every early return.
fn write_theme(output_file: &Path, theme: &Theme, wallpaper: Option<&Path>) -> ExitCode {
    let out_dir = match output_file.parent() {
        Some(parent) if !parent.as_os_str().is_empty() => parent.to_path_buf(),
        _ => PathBuf::from("."),
    };
    if let Err(error) = fs::create_dir_all(&out_dir) {
        return fail(format!("cannot create {}: {error}", out_dir.display()));
    }

    let mut temp = match TempFile::create(&out_dir) {
        Ok(temp) => temp,
        Err(error) => {
            return fail(format!(
                "cannot create a temp file in {}: {error}",
                out_dir.display()
            ))
        }
    };
    let contents = theme.render(&time::utc_timestamp_now());
    if let Err(error) = write_temp_file(temp.path(), contents.as_bytes()) {
        return fail(format!("cannot write {}: {error}", temp.path().display()));
    }

    // A wallpaper change fires the pipeline more than once. The generated
    // file names its source and the moment it was written, so two runs for
    // one wallpaper differ only in that timestamp; compare without it and
    // leave the file alone (no scene reload) when nothing else moved.
    if output_file.is_file() {
        if let Ok(existing) = fs::read(output_file) {
            if strip_stamp(&existing) == strip_stamp(contents.as_bytes()) {
                drop(temp);
                println!("{TOOL}: unchanged ({})", output_file.display());
                return ExitCode::SUCCESS;
            }
        }
    }

    if let Err(error) = fs::rename(temp.path(), output_file) {
        return fail(format!("cannot replace {}: {error}", output_file.display()));
    }
    temp.disarm();

    println!("{TOOL}: wrote {}", output_file.display());
    if let Some(wall) = wallpaper {
        println!("{TOOL}: source {}", wall.display());
    }
    println!(
        "{TOOL}: coal {}  surface {}  ink {}  accent {}",
        theme.coal, theme.surface, theme.ink, theme.accent
    );
    ExitCode::SUCCESS
}

fn write_temp_file(path: &Path, contents: &[u8]) -> io::Result<()> {
    let mut file = OpenOptions::new().write(true).truncate(true).open(path)?;
    file.write_all(contents)?;
    file.flush()?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o644))
}

/// `grep -v -e '^// written:' -e '^// source:'`: drop those lines and keep the
/// rest; like grep, every kept line ends with a newline.
fn strip_stamp(bytes: &[u8]) -> Vec<u8> {
    let mut kept = Vec::with_capacity(bytes.len());
    let mut start = 0;
    while start < bytes.len() {
        let relative_end = bytes[start..]
            .iter()
            .position(|&byte| byte == b'\n')
            .unwrap_or(bytes.len() - start);
        let end = start + relative_end;
        let line = &bytes[start..end];
        if !(line.starts_with(b"// written:") || line.starts_with(b"// source:")) {
            kept.extend_from_slice(line);
            kept.push(b'\n');
        }
        if end == bytes.len() {
            break;
        }
        start = end + 1;
    }
    kept
}

/// A temp file that removes itself unless disarmed after the rename.
struct TempFile {
    path: PathBuf,
    armed: bool,
}

static TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(0);

impl TempFile {
    fn create(directory: &Path) -> io::Result<Self> {
        for _ in 0..100 {
            let path = directory.join(format!(".theme.plm.{}", temp_suffix()));
            match OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o600)
                .open(&path)
            {
                Ok(_) => return Ok(Self { path, armed: true }),
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(error),
            }
        }
        Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            "no unique temp name after 100 attempts",
        ))
    }

    fn path(&self) -> &Path {
        &self.path
    }

    fn disarm(&mut self) {
        self.armed = false;
    }
}

impl Drop for TempFile {
    fn drop(&mut self) {
        if self.armed {
            let _ = fs::remove_file(&self.path);
        }
    }
}

/// Six lower-case base-36 characters, the shape `mktemp` produced.
fn temp_suffix() -> String {
    const ALPHABET: &[u8; 36] = b"0123456789abcdefghijklmnopqrstuvwxyz";
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| u64::from(duration.subsec_nanos()))
        .unwrap_or(0);
    let sequence = TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
    let mut value = (u64::from(std::process::id()) << 32) ^ nanos ^ sequence;
    let mut suffix = String::with_capacity(6);
    for _ in 0..6 {
        suffix.push(char::from(ALPHABET[(value % 36) as usize]));
        value /= 36;
    }
    suffix
}

#[cfg(test)]
mod tests {
    use super::{append_suffix, strip_posix_space, strip_stamp, trim_posix_space};
    use std::ffi::OsStr;

    #[test]
    fn path_suffixes_are_appended_without_normalising() {
        assert_eq!(
            append_suffix(OsStr::new("/tmp/cfg/"), "/pleamar/theme.plm"),
            OsStr::new("/tmp/cfg//pleamar/theme.plm")
        );
        assert_eq!(
            append_suffix(OsStr::new("/tmp/cfg"), "/pleamar/theme.plm"),
            OsStr::new("/tmp/cfg/pleamar/theme.plm")
        );
    }

    #[test]
    fn cache_lines_are_trimmed_of_posix_space_only() {
        assert_eq!(trim_posix_space(b"  /a b/c.png\t\r"), b"/a b/c.png");
        assert_eq!(trim_posix_space(b"\x0b\x0c x \x0c\x0b"), b"x");
        assert_eq!(trim_posix_space(b"   "), b"");
    }

    #[test]
    fn mode_values_lose_every_whitespace_byte() {
        assert_eq!(strip_posix_space(b" l i g h t \n\n"), "light");
        assert_eq!(strip_posix_space(b"auto dark\n"), "autodark");
        assert_eq!(strip_posix_space(b"\xff"), "\u{fffd}");
    }

    #[test]
    fn unchanged_comparison_ignores_the_stamp_and_source() {
        let first =
            b"// theme.plm\n// source:  /a.png\n// written: 2026-01-01T00:00:00Z\nlibrary\n";
        let second =
            b"// theme.plm\n// source:  /b.png\n// written: 2027-02-02T00:00:00Z\nlibrary\n";
        assert_eq!(strip_stamp(first), strip_stamp(second));
        assert_eq!(strip_stamp(first), b"// theme.plm\nlibrary\n".to_vec());
    }

    #[test]
    fn unchanged_comparison_keeps_unterminated_last_lines_like_grep() {
        assert_eq!(strip_stamp(b"a\nb"), b"a\nb\n".to_vec());
        assert_eq!(strip_stamp(b""), Vec::<u8>::new());
    }
}
