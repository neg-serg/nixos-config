//! Hermetic port of `files/pleamar/scripts/theme/test.sh`.
//!
//! Every test gets a throwaway HOME/XDG tree under `$TMPDIR`; the fixture
//! wallpapers are drawn with ImageMagick at test time and nothing touches the
//! network or the developer's real `~/.config`. ImageMagick and jq are the
//! pipeline's own external tools (jq only for `--from-json`), so tests that
//! need them say so and skip with a note when they are absent; the nix package
//! build supplies both.
//!
//! The assertions are the shell suite's: the legacy cache fallback, the
//! canonical cache winning, the golden sampler values, the mode switch file,
//! `--accent`/`--from-json`, the error paths, the unchanged-file shortcut, the
//! 0644 atomic write, and the `theme.default.plm` fallback paragraph.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use pleamar_theme::extract::palette_from_dump;

// ---------------------------------------------------------------------------
// Harness

static SEQUENCE: AtomicU64 = AtomicU64::new(0);

struct TempDir {
    path: PathBuf,
}

impl TempDir {
    fn new(label: &str) -> Self {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_nanos())
            .unwrap_or(0);
        let sequence = SEQUENCE.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "pleamar-theme-test-{label}-{}-{nanos}-{sequence}",
            std::process::id()
        ));
        fs::create_dir_all(&path).expect("test temp directory");
        Self { path }
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

struct Run {
    code: i32,
    stdout: String,
    stderr: String,
}

fn binary() -> PathBuf {
    PathBuf::from(env!("CARGO_BIN_EXE_pleamar-theme"))
}

/// Run the binary with that HOME/XDG, optionally adding environment variables.
fn run_with_env(home: &Path, arguments: &[&str], environment: &[(&str, &str)]) -> Run {
    let mut command = Command::new(binary());
    command
        .args(arguments)
        .env("HOME", home)
        .env("XDG_CONFIG_HOME", home.join(".config"))
        .env("XDG_CACHE_HOME", home.join(".cache"))
        .env_remove("MAGICK_BIN")
        .env_remove("JQ_BIN")
        .env_remove("AWK_BIN");
    for (key, value) in environment {
        command.env(key, value);
    }
    let output = command.output().expect("run pleamar-theme");
    Run {
        code: output.status.code().unwrap_or(-1),
        stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
    }
}

fn run(home: &Path, arguments: &[&str]) -> Run {
    run_with_env(home, arguments, &[])
}

fn theme_path(home: &Path) -> PathBuf {
    home.join(".config/pleamar/theme.plm")
}

fn theme_text(home: &Path) -> String {
    fs::read_to_string(theme_path(home)).expect("generated theme.plm")
}

/// The value of `let skin.NAME = …` in a generated theme.plm.
fn theme_value(text: &str, name: &str) -> String {
    let prefix = format!("let skin.{name} = ");
    text.lines()
        .find_map(|line| line.trim().strip_prefix(&prefix))
        .unwrap_or_else(|| panic!("no skin.{name} in theme.plm:\n{text}"))
        .to_string()
}

fn lower(text: &str) -> String {
    text.to_ascii_lowercase()
}

fn magick_available() -> bool {
    Command::new("magick")
        .arg("-version")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

fn jq_available() -> bool {
    Command::new("jq")
        .arg("--version")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

fn skip(tool: &str) -> bool {
    eprintln!("skipped: {tool} is not on PATH");
    true
}

/// Draw a fixture exactly like test.sh: 320x240.
fn fixture(directory: &Path, name: &str, draw: &str) -> PathBuf {
    let path = directory.join(name);
    let status = Command::new("magick")
        .args(["-size", "320x240", draw])
        .arg(&path)
        .status()
        .expect("run magick");
    assert!(status.success(), "magick failed for {name}");
    path
}

fn fixtures(directory: &Path) -> (PathBuf, PathBuf, PathBuf) {
    (
        fixture(directory, "blue.png", "gradient:#08101e-#2f77b8"),
        fixture(directory, "light.png", "gradient:#f2efe8-#ffffff"),
        fixture(directory, "gray.png", "xc:#9a9a9a"),
    )
}

fn write_cache(home: &Path, name: &str, wallpaper: &Path) {
    let cache = home.join(".cache");
    fs::create_dir_all(&cache).expect("cache dir");
    fs::write(cache.join(name), format!("{}\n", wallpaper.display())).expect("cache file");
}

fn write_canonical_cache(home: &Path, wallpaper: &Path) {
    fs::create_dir_all(home.join(".cache/pleamar")).expect("canonical cache dir");
    write_cache(home, "pleamar/wallpaper-path", wallpaper);
}

/// test.sh's contrast function: the WCAG ratio with the 0.03928 threshold,
/// used only to check the readability assertions.
fn contrast_ratio(first: &str, second: &str) -> f64 {
    fn linear(channel: u8) -> f64 {
        let value = f64::from(channel) / 255.0;
        if value <= 0.039_28 {
            value / 12.92
        } else {
            ((value + 0.055) / 1.055).powf(2.4)
        }
    }
    fn luminance(hex: &str) -> f64 {
        let channel = |range: std::ops::Range<usize>| {
            u8::from_str_radix(&hex[range], 16).expect("hex channel")
        };
        let (r, g, b) = (channel(1..3), channel(3..5), channel(5..7));
        0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
    let first = luminance(first);
    let second = luminance(second);
    let (lighter, darker) = if first < second {
        (second, first)
    } else {
        (first, second)
    };
    (lighter + 0.05) / (darker + 0.05)
}

fn assert_contrast_at_least(ink: &str, surface: &str, minimum: f64, label: &str) {
    let ratio = contrast_ratio(ink, surface);
    assert!(
        ratio >= minimum,
        "{label}: {ink} on {surface} is {ratio:.2}:1, want >= {minimum}"
    );
}

/// The `let skin.*` lines of theme.default.plm; theme.sh's no-wallpaper
/// fallbacks are asserted against this paragraph.
const DEFAULT_LETS: &str = "    let skin.coal = #000000
    let skin.surface = #242A35
    let skin.ink = #CBD6E5
    let skin.ink.dim = #AEB9C8
    let skin.accent = #006FCC
    let skin.accent.hover = mix(skin.accent, #ffffff, 20%)
    let skin.accent.deep = mix(skin.accent, skin.coal, 80%)
    let skin.on.accent = #ffffff
    let skin.light = false
";

fn generated_lets(text: &str) -> String {
    text.lines()
        .filter(|line| line.trim_start().starts_with("let skin."))
        .map(|line| format!("{line}\n"))
        .collect()
}

fn config_dir_entries(home: &Path) -> Vec<String> {
    let mut entries: Vec<String> = fs::read_dir(home.join(".config/pleamar"))
        .map(|directory| {
            directory
                .map(|entry| {
                    entry
                        .expect("entry")
                        .file_name()
                        .to_string_lossy()
                        .into_owned()
                })
                .collect()
        })
        .unwrap_or_default();
    entries.sort();
    entries
}

// ---------------------------------------------------------------------------
// The shell suite

#[test]
fn legacy_cache_path_and_a_coloured_fixture() {
    if !magick_available() {
        skip("magick");
        return;
    }
    let work = TempDir::new("legacy");
    let (blue, _light, _gray) = fixtures(work.path());
    let home = work.path().join("home1");
    fs::create_dir_all(home.join(".cache")).expect("cache");
    fs::create_dir_all(home.join(".config/pleamar")).expect("config");
    fs::write(home.join(".config/pleamar/keep.txt"), "sentinel\n").expect("keep");
    write_cache(&home, "quickshell-wallpaper-path", &blue);

    let result = run(&home, &[]);
    assert_eq!(result.code, 0, "stderr: {}", result.stderr);
    let text = theme_text(&home);
    assert!(
        text.lines().any(|line| line == "library Skin strict {"),
        "not a strict Skin library:\n{text}"
    );
    assert!(
        text.contains("let skin.on.accent = #ffffff"),
        "the eight skin names are not declared:\n{text}"
    );

    // The sampler is asserted directly: theme.plm carries the shell's own
    // tones and only the wallpaper's accent, so the greeter's palette is
    // checked through the same extractor the binary uses.
    let dump = Command::new("magick")
        .args(["-define", "jpeg:size=384x384"])
        .arg(&blue)
        .args([
            "-auto-orient",
            "-colorspace",
            "sRGB",
            "-thumbnail",
            "48x48!",
            "-alpha",
            "off",
            "-depth",
            "8",
            "txt:-",
        ])
        .output()
        .expect("magick dump");
    let palette =
        palette_from_dump(&String::from_utf8_lossy(&dump.stdout)).expect("sampled palette");
    assert_eq!(palette.coal.hex(), "#061c38", "coal = darkest cluster");
    assert_eq!(palette.surface.hex(), "#023663", "surface = second cluster");
    assert_eq!(palette.ink.hex(), "#66a6d7", "ink is light and readable");
    assert_eq!(palette.accent.hex(), "#0067cc", "accent hue-matched mean");

    assert_eq!(theme_value(&text, "coal"), "#000000");
    assert_eq!(lower(&theme_value(&text, "surface")), "#242a35");
    assert_eq!(lower(&theme_value(&text, "ink")), "#cbd6e5");
    assert_eq!(theme_value(&text, "accent"), "#0067cc");
    assert_eq!(lower(&theme_value(&text, r"ink.dim")), "#aeb9c8");
    assert_eq!(theme_value(&text, "light"), "false");
    assert_eq!(
        fs::read_to_string(home.join(".config/pleamar/keep.txt")).expect("keep.txt"),
        "sentinel\n",
        "nothing else under ~/.config/pleamar is touched"
    );
}

#[test]
fn the_canonical_cache_path_wins_over_the_legacy_one() {
    if !magick_available() {
        skip("magick");
        return;
    }
    let work = TempDir::new("canonical");
    let (blue, light, _gray) = fixtures(work.path());
    let home = work.path().join("home2");
    write_canonical_cache(&home, &light);
    write_cache(&home, "quickshell-wallpaper-path", &blue);

    let result = run(&home, &[]);
    assert_eq!(result.code, 0, "stderr: {}", result.stderr);
    assert!(
        result
            .stdout
            .contains(&format!("source {}", light.display())),
        "INTERFACES §1.2 path did not win: {}",
        result.stdout
    );
    let text = theme_text(&home);
    let ink = lower(&theme_value(&text, "ink"));
    let surface = lower(&theme_value(&text, "surface"));
    assert_contrast_at_least(&ink, &surface, 4.5, "light fixture");
    assert_eq!(theme_value(&text, "light"), "true");
}

#[test]
fn mode_flag_and_mode_file_flip_the_palette() {
    if !magick_available() {
        skip("magick");
        return;
    }
    let work = TempDir::new("mode");
    let (blue, light, _gray) = fixtures(work.path());
    let home = work.path().join("home3");
    write_canonical_cache(&home, &light);

    let result = run(&home, &["--mode", "dark"]);
    assert_eq!(result.code, 0, "stderr: {}", result.stderr);
    let text = theme_text(&home);
    assert_eq!(theme_value(&text, "coal"), "#000000");
    assert_eq!(theme_value(&text, "light"), "false");

    fs::write(home.join(".config/pleamar/theme.mode"), "light\n").expect("theme.mode");
    write_canonical_cache(&home, &blue);
    let result = run(&home, &[]);
    assert_eq!(result.code, 0, "stderr: {}", result.stderr);
    let text = theme_text(&home);
    assert_eq!(theme_value(&text, "coal"), "#F6F3F8");
    assert_eq!(theme_value(&text, "light"), "true");
    assert_contrast_at_least(
        &theme_value(&text, "ink"),
        &theme_value(&text, "coal"),
        4.5,
        "light theme",
    );

    fs::remove_file(home.join(".config/pleamar/theme.mode")).expect("remove theme.mode");
    let result = run(&home, &[]);
    assert_eq!(result.code, 0, "stderr: {}", result.stderr);
    assert_eq!(theme_value(&theme_text(&home), "coal"), "#000000");

    let result = run(&home, &["--mode", "blue"]);
    assert_eq!(result.code, 2, "an unknown mode is a usage error");
}

#[test]
fn accent_override_keeps_the_shells_tones() {
    if !magick_available() {
        skip("magick");
        return;
    }
    let work = TempDir::new("accent");
    let (blue, _light, _gray) = fixtures(work.path());
    let home = work.path().join("home1");
    write_cache(&home, "quickshell-wallpaper-path", &blue);

    let result = run(&home, &["--accent", "#AbCdEf"]);
    assert_eq!(result.code, 0, "stderr: {}", result.stderr);
    let text = theme_text(&home);
    assert_eq!(theme_value(&text, "accent"), "#abcdef");
    assert_eq!(theme_value(&text, "coal"), "#000000");
}

#[test]
fn from_json_without_a_wallpaper_takes_the_named_tones() {
    if !jq_available() {
        skip("jq");
        return;
    }
    let work = TempDir::new("json");
    let home = work.path().join("home4");
    fs::create_dir_all(&home).expect("home");
    let palette = work.path().join("pal.json");
    fs::write(
        &palette,
        "{\"surface\": \"#101820\", \"ink\": \"#f0ead6\", \"accent\": \"#12ab34\"}\n",
    )
    .expect("pal.json");

    let result = run(&home, &["--from-json", palette.to_str().expect("path")]);
    assert_eq!(result.code, 0, "stderr: {}", result.stderr);
    let text = theme_text(&home);
    assert_eq!(theme_value(&text, "surface"), "#101820");
    assert_eq!(theme_value(&text, "ink"), "#f0ead6");
    assert_eq!(theme_value(&text, "accent"), "#12ab34");
    assert_eq!(theme_value(&text, "coal"), "#000000");
}

#[test]
fn missing_input_is_an_error_and_writes_nothing() {
    let work = TempDir::new("missing");
    let home = work.path().join("home5");
    fs::create_dir_all(&home).expect("home");

    let result = run(&home, &[]);
    assert_eq!(result.code, 1);
    assert!(!theme_path(&home).exists(), "theme.plm was written");
    assert!(
        result.stderr.contains("nothing to extract"),
        "stderr: {}",
        result.stderr
    );
}

#[test]
fn a_failed_run_leaves_the_previous_file_and_no_temp() {
    if !magick_available() {
        skip("magick");
        return;
    }
    let work = TempDir::new("failed-run");
    let (blue, _light, _gray) = fixtures(work.path());
    let home = work.path().join("home6");
    write_cache(&home, "quickshell-wallpaper-path", &blue);
    assert_eq!(run(&home, &[]).code, 0);

    let before = fs::read(theme_path(&home)).expect("before");
    let result = run(&home, &["--accent", "not-a-colour"]);
    assert_eq!(result.code, 1);
    let after = fs::read(theme_path(&home)).expect("after");
    assert_eq!(before, after, "theme.plm changed on a bad input");
    let leftovers: Vec<_> = fs::read_dir(home.join(".config/pleamar"))
        .expect("config dir")
        .filter_map(|entry| {
            let entry = entry.expect("entry");
            entry
                .file_name()
                .to_string_lossy()
                .starts_with(".theme.plm.")
                .then(|| entry.path())
        })
        .collect();
    assert!(leftovers.is_empty(), "temp files left: {leftovers:?}");
}

#[test]
fn the_fallback_palette_matches_theme_default() {
    let work = TempDir::new("fallback");
    let home = work.path().join("home4");
    fs::create_dir_all(&home).expect("home");
    let result = run(&home, &["--accent", "#006fcc"]);
    assert_eq!(result.code, 0, "stderr: {}", result.stderr);
    assert_eq!(
        lower(&generated_lets(&theme_text(&home))),
        lower(DEFAULT_LETS),
        "theme.default.plm paragraph differs from the no-wallpaper fallbacks"
    );
}

#[test]
fn help_lists_the_options() {
    let work = TempDir::new("help");
    let result = run(work.path(), &["--help"]);
    assert_eq!(result.code, 0);
    assert!(
        result.stdout.contains("--from-json"),
        "stdout: {}",
        result.stdout
    );
    assert!(
        result
            .stdout
            .starts_with("theme.sh — build ~/.config/pleamar/theme.plm"),
        "usage text changed: {}",
        result.stdout
    );
}

#[test]
fn short_help_is_the_same_text() {
    let work = TempDir::new("short-help");
    let long = run(work.path(), &["--help"]);
    let short = run(work.path(), &["-h"]);
    assert_eq!(short.code, 0);
    assert_eq!(short.stdout, long.stdout);
}

#[test]
fn home_is_required_before_help() {
    for arguments in [vec![], vec!["--help"]] {
        let output = Command::new(binary())
            .args(&arguments)
            .env_remove("HOME")
            .env_remove("XDG_CONFIG_HOME")
            .env_remove("XDG_CACHE_HOME")
            .output()
            .expect("run pleamar-theme");
        assert_eq!(output.status.code(), Some(1), "{arguments:?}");
        assert_eq!(
            String::from_utf8_lossy(&output.stderr),
            "theme: HOME is not set — nothing to write\n"
        );
    }
}

#[test]
fn xdg_defaults_fall_back_to_home() {
    if !magick_available() {
        skip("magick");
        return;
    }
    let work = TempDir::new("xdg-defaults");
    let (blue, _light, _gray) = fixtures(work.path());
    let home = work.path().join("home");
    fs::create_dir_all(home.join(".cache")).expect("cache");
    fs::write(
        home.join(".cache/quickshell-wallpaper-path"),
        format!("{}\n", blue.display()),
    )
    .expect("cache file");

    let output = Command::new(binary())
        .env("HOME", &home)
        .env_remove("XDG_CONFIG_HOME")
        .env_remove("XDG_CACHE_HOME")
        .env_remove("MAGICK_BIN")
        .output()
        .expect("run pleamar-theme");
    assert_eq!(output.status.code(), Some(0));
    let generated = home.join(".config/pleamar/theme.plm");
    assert!(
        generated.is_file(),
        "no theme.plm at the default config path"
    );
    let text = fs::read_to_string(generated).expect("theme.plm");
    assert_eq!(theme_value(&text, "accent"), "#0067cc");
}

#[test]
fn explicit_wallpaper_wins_over_the_cache() {
    if !magick_available() {
        skip("magick");
        return;
    }
    let work = TempDir::new("explicit");
    let (blue, light, _gray) = fixtures(work.path());
    let home = work.path().join("home");
    write_cache(&home, "quickshell-wallpaper-path", &blue);

    let result = run(&home, &["--wallpaper", light.to_str().expect("path")]);
    assert_eq!(result.code, 0, "stderr: {}", result.stderr);
    assert!(result
        .stdout
        .contains(&format!("source {}", light.display())));
    assert_eq!(theme_value(&theme_text(&home), "light"), "true");
}

#[test]
fn trailing_slashes_keep_the_shells_path_spelling() {
    if !magick_available() {
        skip("magick");
        return;
    }
    let work = TempDir::new("slashes");
    let (blue, _light, _gray) = fixtures(work.path());
    let home = work.path().join("home");
    let config = work.path().join("cfg");
    let cache = work.path().join("cache");
    fs::create_dir_all(&home).expect("home");
    fs::create_dir_all(config.join("pleamar")).expect("config");
    fs::create_dir_all(cache.join("pleamar")).expect("cache");
    fs::write(config.join("pleamar/theme.mode"), "light\n").expect("theme.mode");
    fs::write(
        cache.join("pleamar/wallpaper-path"),
        format!("{}\n", blue.display()),
    )
    .expect("cache file");
    let config_env = format!("{}/", config.display());
    let cache_env = format!("{}/", cache.display());

    let output = Command::new(binary())
        .env("HOME", &home)
        .env("XDG_CONFIG_HOME", &config_env)
        .env("XDG_CACHE_HOME", &cache_env)
        .env_remove("MAGICK_BIN")
        .env_remove("JQ_BIN")
        .output()
        .expect("run pleamar-theme");
    assert_eq!(output.status.code(), Some(0));
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(
        stdout.contains(&format!("wrote {config_env}/pleamar/theme.plm")),
        "stdout: {stdout}"
    );
    let text = fs::read_to_string(config.join("pleamar/theme.plm")).expect("theme.plm");
    assert!(
        text.contains(&format!(
            "// mode:    light (forced light by {config_env}/pleamar/theme.mode)"
        )),
        "mode line: {text}"
    );
}

#[test]
fn a_second_run_for_the_same_wallpaper_is_unchanged() {
    if !magick_available() {
        skip("magick");
        return;
    }
    let work = TempDir::new("unchanged");
    let (blue, _light, _gray) = fixtures(work.path());
    let home = work.path().join("home");
    write_cache(&home, "quickshell-wallpaper-path", &blue);
    assert_eq!(run(&home, &[]).code, 0);
    let first = theme_text(&home);

    let result = run(&home, &[]);
    assert_eq!(result.code, 0, "stderr: {}", result.stderr);
    assert_eq!(
        result.stdout,
        format!("theme: unchanged ({})\n", theme_path(&home).display())
    );
    assert_eq!(theme_text(&home), first, "the file was rewritten");
}

#[test]
fn the_file_is_written_atomically_with_mode_0644() {
    if !magick_available() {
        skip("magick");
        return;
    }
    let work = TempDir::new("permissions");
    let (blue, _light, _gray) = fixtures(work.path());
    let home = work.path().join("home");
    write_cache(&home, "quickshell-wallpaper-path", &blue);
    let cache_before = fs::read(home.join(".cache/quickshell-wallpaper-path")).expect("cache");
    assert_eq!(run(&home, &[]).code, 0);

    let metadata = fs::metadata(theme_path(&home)).expect("theme.plm");
    assert_eq!(metadata.permissions().mode() & 0o777, 0o644);
    let entries = config_dir_entries(&home);
    assert_eq!(
        entries,
        vec!["theme.plm".to_string()],
        "unexpected files: {entries:?}"
    );
    assert_eq!(
        fs::read(home.join(".cache/quickshell-wallpaper-path")).expect("cache"),
        cache_before,
        "the pipeline wrote to the cache"
    );
}

#[test]
fn usage_and_input_errors_match_the_shell() {
    let work = TempDir::new("errors");
    let home = work.path().join("home");
    fs::create_dir_all(&home).expect("home");

    let result = run(&home, &["--nope"]);
    assert_eq!(result.code, 2);
    assert_eq!(
        result.stderr,
        "theme: unknown argument: --nope\ntheme: see --help\n"
    );

    for (arguments, message) in [
        (vec!["--wallpaper"], "--wallpaper needs a FILE"),
        (vec!["--accent"], "--accent needs a '#RRGGBB' value"),
        (vec!["--from-json"], "--from-json needs a FILE"),
        (vec!["--mode"], "--mode needs auto, light or dark"),
    ] {
        let result = run(&home, &arguments);
        assert_eq!(result.code, 2, "{arguments:?}");
        assert_eq!(
            result.stderr,
            format!("theme: {message}\ntheme: see --help\n"),
            "{arguments:?}"
        );
    }

    let missing = work.path().join("missing.png");
    let result = run(&home, &["--wallpaper", missing.to_str().expect("path")]);
    assert_eq!(result.code, 1);
    assert_eq!(
        result.stderr,
        format!(
            "theme: --wallpaper: not a readable file: {}\n",
            missing.display()
        )
    );

    // The mode is validated after the "nothing to extract" check, so give the
    // run a colour to reach it.
    let result = run(&home, &["--accent", "#112233", "--mode", "sepia"]);
    assert_eq!(result.code, 2);
    assert_eq!(
        result.stderr,
        "theme: --mode: expected auto, light or dark: sepia\ntheme: see --help\n"
    );
}

#[test]
fn tool_errors_report_the_overridden_names() {
    let work = TempDir::new("tools");
    let home = work.path().join("home");
    fs::create_dir_all(&home).expect("home");

    if magick_available() {
        let (blue, _light, _gray) = fixtures(work.path());
        write_cache(&home, "quickshell-wallpaper-path", &blue);
        let result = run_with_env(&home, &[], &[("MAGICK_BIN", "/nonexistent/magick")]);
        // The shell's tool check ran inside a command substitution, so the
        // missing tool warned and continued; the run ends with exit 1 because
        // nothing was extracted.
        assert_eq!(result.code, 1);
        assert!(
            result.stderr.contains("no '/nonexistent/magick' on PATH"),
            "stderr: {}",
            result.stderr
        );
        assert!(
            result.stderr.contains("cannot sample"),
            "stderr: {}",
            result.stderr
        );
    }

    if jq_available() {
        let palette = work.path().join("pal.json");
        fs::write(&palette, "{\"accent\": \"#112233\"}\n").expect("pal.json");
        let result = run_with_env(
            &home,
            &["--from-json", palette.to_str().expect("path")],
            &[("JQ_BIN", "/nonexistent/jq")],
        );
        assert_eq!(result.code, 2);
        assert_eq!(
            result.stderr,
            "theme: no '/nonexistent/jq' on PATH (JQ_BIN overrides it); jq is needed for --from-json\n"
        );
    }
}

#[test]
fn json_errors_and_short_forms() {
    if !jq_available() {
        skip("jq");
        return;
    }
    let work = TempDir::new("json-errors");
    let home = work.path().join("home");
    fs::create_dir_all(&home).expect("home");

    let invalid = work.path().join("bad.json");
    fs::write(&invalid, "not json\n").expect("bad.json");
    let result = run(&home, &["--from-json", invalid.to_str().expect("path")]);
    assert_eq!(result.code, 1);
    assert_eq!(
        result.stderr,
        format!(
            "theme: --from-json: no coal/surface/ink/accent string in {}\n",
            invalid.display()
        )
    );

    let empty = work.path().join("empty.json");
    fs::write(&empty, "{}\n").expect("empty.json");
    let result = run(&home, &["--from-json", empty.to_str().expect("path")]);
    assert_eq!(result.code, 1);

    let short = work.path().join("short.json");
    fs::write(&short, "{\"coal\": \"#AbC\", \"accent\": 42}\n").expect("short.json");
    let result = run(&home, &["--from-json", short.to_str().expect("path")]);
    assert_eq!(result.code, 0, "stderr: {}", result.stderr);
    let text = theme_text(&home);
    assert_eq!(theme_value(&text, "coal"), "#aabbcc");
    assert_eq!(
        theme_value(&text, "accent"),
        "#006FCC",
        "numeric values are skipped"
    );

    let empty_string = work.path().join("empty-string.json");
    fs::write(&empty_string, "{\"accent\": \"\"}\n").expect("empty-string.json");
    let result = run(
        &home,
        &["--from-json", empty_string.to_str().expect("path")],
    );
    assert_eq!(result.code, 1, "an empty JSON string is not a colour");

    let bad_value = work.path().join("bad-value.json");
    fs::write(&bad_value, "{\"ink\": \"blue\"}\n").expect("bad-value.json");
    let result = run(&home, &["--from-json", bad_value.to_str().expect("path")]);
    assert_eq!(result.code, 1);
    assert_eq!(
        result.stderr,
        "theme: --from-json: ink is not a '#RRGGBB' colour: blue\n"
    );
}

#[test]
fn a_failed_sample_is_tolerated_when_a_colour_is_given() {
    if !magick_available() {
        skip("magick");
        return;
    }
    let work = TempDir::new("bad-image");
    let home = work.path().join("home");
    let text_file = work.path().join("not-an-image.txt");
    fs::write(&text_file, "hello\n").expect("text file");
    write_canonical_cache(&home, &text_file);

    let result = run(&home, &["--accent", "#112233"]);
    assert_eq!(result.code, 0, "stderr: {}", result.stderr);
    assert!(
        result.stderr.contains("cannot sample"),
        "stderr: {}",
        result.stderr
    );
    let text = theme_text(&home);
    assert_eq!(theme_value(&text, "accent"), "#112233");
    assert_eq!(theme_value(&text, "coal"), "#000000");
}

#[test]
fn forced_modes_use_the_switch_file_and_ignore_its_whitespace() {
    if !magick_available() {
        skip("magick");
        return;
    }
    let work = TempDir::new("mode-file");
    let (blue, _light, _gray) = fixtures(work.path());
    let home = work.path().join("home");
    write_cache(&home, "quickshell-wallpaper-path", &blue);
    fs::create_dir_all(home.join(".config/pleamar")).expect("config");
    fs::write(home.join(".config/pleamar/theme.mode"), " l i g h t \n\n").expect("theme.mode");

    let result = run(&home, &[]);
    assert_eq!(result.code, 0, "stderr: {}", result.stderr);
    assert_eq!(theme_value(&theme_text(&home), "light"), "true");

    fs::write(home.join(".config/pleamar/theme.mode"), "auto dark\n").expect("theme.mode");
    let result = run(&home, &[]);
    assert_eq!(result.code, 2);
    assert_eq!(
        result.stderr,
        "theme: --mode: expected auto, light or dark: autodark\ntheme: see --help\n"
    );
}

#[test]
fn empty_values_are_absent_like_the_shells_dash_n() {
    if !magick_available() {
        skip("magick");
        return;
    }
    let work = TempDir::new("empty-values");
    let (blue, _light, _gray) = fixtures(work.path());
    let home = work.path().join("home");
    write_cache(&home, "quickshell-wallpaper-path", &blue);

    // --wallpaper '' falls back to the cache and --accent '' keeps sampling.
    let result = run(&home, &["--wallpaper", "", "--accent", ""]);
    assert_eq!(result.code, 0, "stderr: {}", result.stderr);
    assert_eq!(theme_value(&theme_text(&home), "accent"), "#0067cc");

    // --from-json '' is not an explicit colour either.
    let bare = work.path().join("bare");
    fs::create_dir_all(&bare).expect("bare home");
    let result = run(&bare, &["--from-json", ""]);
    assert_eq!(result.code, 1);
    assert!(result.stderr.contains("nothing to extract"));
}

#[test]
fn the_generated_file_names_the_wallpaper_source() {
    if !magick_available() {
        skip("magick");
        return;
    }
    let work = TempDir::new("source");
    let (blue, _light, _gray) = fixtures(work.path());
    let home = work.path().join("home");
    write_cache(&home, "quickshell-wallpaper-path", &blue);

    let result = run(&home, &[]);
    assert_eq!(result.code, 0, "stderr: {}", result.stderr);
    assert_eq!(
        result.stdout,
        format!(
            "theme: wrote {}\ntheme: source {}\ntheme: coal #000000  surface #242A35  ink #CBD6E5  accent #0067cc\n",
            theme_path(&home).display(),
            blue.display()
        )
    );
    let text = theme_text(&home);
    assert!(text.contains(&format!("// source:  {}\n", blue.display())));
    assert!(text.contains("// mode:    dark (auto: the wallpaper is dark)\n"));
}

/// test.sh's optional compiler check: a /tmp consumer imports the generated
/// file. Only runs when PLEAMAR_BIN names a compiler and this checkout still
/// has `files/pleamar/lib`; the nix build leaves it skipped.
#[test]
fn an_optional_consumer_still_compiles() {
    let Ok(pleamar) = std::env::var("PLEAMAR_BIN") else {
        eprintln!("skipped: PLEAMAR_BIN is not set");
        return;
    };
    let repository = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let library = repository.join("files/pleamar/lib");
    if !Path::new(&pleamar).is_file() || !library.is_dir() {
        eprintln!("skipped: no compiler or no files/pleamar/lib");
        return;
    }
    let work = TempDir::new("consumer");
    let home = work.path().join("home");
    fs::create_dir_all(&home).expect("home");
    let result = run(&home, &["--accent", "#006fcc"]);
    assert_eq!(result.code, 0, "stderr: {}", result.stderr);

    let consumer_dir = work.path().join("consumer");
    fs::create_dir_all(&consumer_dir).expect("consumer dir");
    let relative_library = path_relative(&consumer_dir, &library);
    let relative_theme = path_relative(&consumer_dir, &theme_path(&home));
    let consumer = format!(
        "import \"{relative_library}/palette.plm\"\n\
         import \"{relative_library}/capsule.plm\"\n\
         import \"{relative_theme}\"\n\
         \n\
         scene ThemeProof {{\n\
             surface {{ size: 320, 96; anchor: center }}\n\
             group zoom {{\n\
                 scale: ui\n\
                 Capsule(180, 40, fill: skin.surface, alpha: 1, scale: 1, rim: 0.05) {{\n\
                     text \"welcome\" {{ size: 14; color: skin.ink }}\n\
                     text \"dim\" {{ size: 12; color: skin.ink.dim }}\n\
                 }}\n\
                 box {{ from: 0, 0; size: 180, 3; corner: 1; color: skin.accent }}\n\
                 box {{ from: 0, 3; size: 90, 3; corner: 1; color: skin.accent.hover }}\n\
                 box {{ from: 90, 3; size: 90, 3; corner: 1; color: skin.accent.deep }}\n\
                 text \"x\" {{ at: 4, 30; size: 12; color: skin.on.accent }}\n\
             }}\n\
         }}\n"
    );
    let file = consumer_dir.join("theme_proof.plm");
    fs::write(&file, consumer).expect("consumer scene");
    let output = Command::new(&pleamar)
        .arg("--check")
        .arg(&file)
        .env_remove("LD_LIBRARY_PATH")
        .output()
        .expect("run the compiler");
    assert!(
        output.status.success(),
        "consumer did not compile: {}",
        String::from_utf8_lossy(&output.stderr)
    );
}

/// `realpath --relative-to`: only the simple case the consumer test needs.
fn path_relative(from: &Path, to: &Path) -> String {
    let from: Vec<_> = from.components().collect();
    let to: Vec<_> = to.components().collect();
    let common = from
        .iter()
        .zip(to.iter())
        .take_while(|(left, right)| left == right)
        .count();
    let mut relative = PathBuf::new();
    for _ in common..from.len() {
        relative.push("..");
    }
    for component in &to[common..] {
        relative.push(component.as_os_str());
    }
    relative.to_string_lossy().into_owned()
}
