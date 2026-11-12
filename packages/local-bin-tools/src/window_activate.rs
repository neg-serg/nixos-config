//! window-activate — raise a Hyprland window by class or title.
//!
//! Qt's Wayland client implements no `xdg-activation`, so Telegram's tray entry
//! "Open Telegram" does nothing by itself; Hyprland can still be asked directly
//! through the Lua `focus` dispatcher, which also focuses windows sitting on a
//! hidden special workspace. This is that ask as a CLI.
//!
//!     window-activate --list                        every window: "class<TAB>title"
//!     window-activate org.telegram.desktop          exact class
//!     window-activate --class telegram --substring  case-insensitive substring
//!     window-activate --title 'птичка'              case-insensitive substring
//!     window-activate --raise-for TelegramDesktop   "the window of this tray item"
//!     window-activate --open-prefix                 labels that mean "bring it up"
//!
//! Reports go to stderr (so a caller can keep stdout clean) unless
//! `--stdout-report` is given. Exit codes: 0 raised (or listed), 1 nothing
//! matched, 2 usage / no hyprctl.
//!
//! Port of `packages/local-bin/bin/window-activate`. `WINDOW_ACTIVATE_HYPRCTL`
//! and `WINDOW_ACTIVATE_HINTS` override the binary and the tray→class table
//! (tests).

mod json;

use std::path::PathBuf;
use std::process::{Command, Stdio};

/// Labels that promise "bring it up"; tray menus are translated, so both
/// languages are covered. The comparison is a prefix one, so "Quit Telegram"
/// and "Minimize to tray" never count as an open.
const OPEN_LABELS: [&str; 5] = ["open", "show", "открыть", "показать", "развернуть"];

fn env_or(name: &str, fallback: &str) -> String {
    match std::env::var(name) {
        Ok(value) if !value.is_empty() => value,
        _ => fallback.to_string(),
    }
}

fn hints_path() -> PathBuf {
    if let Ok(value) = std::env::var("WINDOW_ACTIVATE_HINTS") {
        if !value.is_empty() {
            return PathBuf::from(value);
        }
    }
    let base = match std::env::var("XDG_CONFIG_HOME") {
        Ok(value) if !value.is_empty() => PathBuf::from(value),
        _ => PathBuf::from(env_or("HOME", "/")).join(".config"),
    };
    base.join("menu-search").join("window-class.tsv")
}

/// `id<TAB>window class` pairs from the shared table.
pub fn window_class_hints() -> Vec<(String, String)> {
    let Ok(text) = std::fs::read_to_string(hints_path()) else {
        return Vec::new();
    };
    let mut hints = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let fields: Vec<&str> = line
            .split('\t')
            .map(str::trim)
            .filter(|field| !field.is_empty())
            .collect();
        if fields.len() >= 2 {
            hints.push((fields[0].to_string(), fields[1].to_string()));
        }
    }
    hints
}

fn hyprctl_bin() -> String {
    env_or("WINDOW_ACTIVATE_HYPRCTL", "hyprctl")
}

fn hyprctl(args: &[&str]) -> Result<String, String> {
    let output = Command::new(hyprctl_bin())
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .map_err(|_| "hyprctl not found — window-activate drives Hyprland".to_string())?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let detail = if stderr.is_empty() { stdout } else { stderr };
        return Err(format!("hyprctl {} failed: {detail}", args.join(" ")));
    }
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

/// One window from `hyprctl clients -j`.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Window {
    pub class: String,
    pub initial_class: String,
    pub title: String,
    pub workspace: String,
    pub focus_history: i64,
}

impl Window {
    pub fn app_id(&self) -> &str {
        if !self.class.is_empty() {
            &self.class
        } else {
            &self.initial_class
        }
    }
}

fn text_field(value: &json::Value, key: &str) -> String {
    value
        .get(key)
        .and_then(json::Value::as_str)
        .unwrap_or("")
        .to_string()
}

pub fn windows() -> Result<Vec<Window>, String> {
    let out = hyprctl(&["clients", "-j"])?;
    let Some(json::Value::Array(items)) = json::parse(&out) else {
        // An empty client list makes some hyprland versions print nothing at all.
        return Ok(Vec::new());
    };
    Ok(items
        .iter()
        .map(|item| {
            let workspace = match item.get("workspace") {
                Some(workspace) => {
                    let name = text_field(workspace, "name");
                    if name.is_empty() {
                        match workspace.get("id") {
                            Some(json::Value::Number(number)) => format!("{}", *number as i64),
                            Some(json::Value::Str(text)) => text.clone(),
                            _ => "?".to_string(),
                        }
                    } else {
                        name
                    }
                }
                None => "?".to_string(),
            };
            Window {
                class: text_field(item, "class"),
                initial_class: text_field(item, "initialClass"),
                title: text_field(item, "title"),
                workspace,
                focus_history: match item.get("focusHistoryID") {
                    Some(json::Value::Number(number)) => *number as i64,
                    _ => 10_000,
                },
            }
        })
        .collect())
}

/// A Lua string literal safe to paste into `hyprctl dispatch`.
pub fn lua_string(value: &str) -> String {
    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
}

/// Python's `re.escape`, which only escapes the regex metacharacters.
pub fn re_escape(text: &str) -> String {
    const SPECIAL: &str = "()[]{}?*+-|^$\\.&~# \t\n\r\u{b}\u{c}";
    let mut out = String::with_capacity(text.len());
    for ch in text.chars() {
        if SPECIAL.contains(ch) {
            out.push('\\');
        }
        out.push(ch);
    }
    out
}

fn by_recency(windows: &[Window]) -> Window {
    let mut best = &windows[0];
    for window in windows.iter() {
        if window.focus_history < best.focus_history {
            best = window;
        }
    }
    best.clone()
}

/// The window behind a tray item: its id, then its name, against class and
/// title. The tray registry and the windows disagree about naming more often
/// than one would hope (`TelegramDesktop` vs `org.telegram.desktop`), so each
/// candidate is checked both ways round.
pub fn pick_window(windows: &[Window], tray_id: &str, tray_title: &str) -> Option<Window> {
    let needles: Vec<&str> = [tray_id, tray_title]
        .iter()
        .map(|value| value.trim())
        .filter(|value| !value.is_empty())
        .collect();
    if needles.is_empty() {
        return None;
    }
    let hints = window_class_hints();
    // The explicit hint for this id wins over everything else.
    if let Some((_, hint)) = hints.iter().find(|(id, _)| id == needles[0]) {
        let hinted: Vec<Window> = windows
            .iter()
            .filter(|window| {
                window
                    .app_id()
                    .to_lowercase()
                    .contains(&hint.to_lowercase())
            })
            .cloned()
            .collect();
        if !hinted.is_empty() {
            return Some(by_recency(&hinted));
        }
    }
    for needle in needles {
        let low = needle.to_lowercase();
        let found: Vec<Window> = windows
            .iter()
            .filter(|window| {
                let class = window.app_id().to_lowercase();
                low.contains(&class)
                    || class.contains(&low)
                    || window.title.to_lowercase().contains(&low)
            })
            .cloned()
            .collect();
        if !found.is_empty() {
            return Some(by_recency(&found));
        }
    }
    None
}

pub fn matches(
    window: &Window,
    want_class: Option<&str>,
    want_title: Option<&str>,
    substring: bool,
) -> bool {
    if let Some(want) = want_class {
        let class = window.app_id();
        if substring {
            if class.to_lowercase().contains(&want.to_lowercase()) {
                return true;
            }
        } else if class == want {
            return true;
        }
    }
    if let Some(want) = want_title {
        if window.title.to_lowercase().contains(&want.to_lowercase()) {
            return true;
        }
    }
    false
}

fn report(message: &str, to_stdout: bool) {
    if to_stdout {
        println!("{message}");
    } else {
        eprintln!("{message}");
    }
}

struct Options {
    window_class: Option<String>,
    class_opt: Option<String>,
    title: Option<String>,
    substring: bool,
    list: bool,
    raise_for: Option<String>,
    open_prefix: bool,
    stdout_report: bool,
    tray_title: String,
}

fn parse_args() -> Result<Options, String> {
    let mut options = Options {
        window_class: None,
        class_opt: None,
        title: None,
        substring: false,
        list: false,
        raise_for: None,
        open_prefix: false,
        stdout_report: false,
        tray_title: String::new(),
    };
    let mut args = std::env::args().skip(1).peekable();
    while let Some(argument) = args.next() {
        let mut value = |name: &str| -> Result<String, String> {
            args.next().ok_or_else(|| format!("{name} expects a value"))
        };
        match argument.as_str() {
            "--class" => options.class_opt = Some(value("--class")?),
            "--title" => options.title = Some(value("--title")?),
            "--substring" => options.substring = true,
            "--list" => options.list = true,
            "--raise-for" => options.raise_for = Some(value("--raise-for")?),
            "--tray-title" => options.tray_title = value("--tray-title")?,
            "--open-prefix" => options.open_prefix = true,
            "--stdout-report" => options.stdout_report = true,
            "-h" | "--help" => return Err("help".to_string()),
            other if other.starts_with('-') => {
                return Err(format!("unrecognized argument {other}"))
            }
            other => options.window_class = Some(other.to_string()),
        }
    }
    Ok(options)
}

fn main() -> std::process::ExitCode {
    let options = match parse_args() {
        Ok(options) => options,
        Err(message) => {
            if message == "help" {
                println!("usage: window-activate [--list|--open-prefix|CLASS|--class C|--title T|--raise-for ID]");
                return std::process::ExitCode::SUCCESS;
            }
            eprintln!("window-activate: {message}");
            return std::process::ExitCode::from(2);
        }
    };

    if options.open_prefix {
        for label in OPEN_LABELS {
            println!("{label}");
        }
        return std::process::ExitCode::SUCCESS;
    }

    let want_class = options.class_opt.clone().or(options.window_class.clone());
    if !options.list
        && options.raise_for.is_none()
        && want_class.is_none()
        && options.title.is_none()
    {
        eprintln!(
            "window-activate: a window class, --class, --title, --raise-for or --list is required"
        );
        return std::process::ExitCode::from(2);
    }

    let open_windows = match windows() {
        Ok(windows) => windows,
        Err(exc) => {
            eprintln!("window-activate: {exc}");
            return std::process::ExitCode::from(2);
        }
    };

    if options.list {
        for window in &open_windows {
            println!("{}\t{}\t[{}]", window.class, window.title, window.workspace);
        }
        return std::process::ExitCode::SUCCESS;
    }

    let target = match &options.raise_for {
        Some(tray_id) => pick_window(&open_windows, tray_id, &options.tray_title),
        None => open_windows
            .iter()
            .find(|window| {
                matches(
                    window,
                    want_class.as_deref(),
                    options.title.as_deref(),
                    options.substring,
                )
            })
            .cloned(),
    };
    let Some(target) = target else {
        let what = options
            .raise_for
            .clone()
            .or(want_class.clone())
            .or(options.title.clone())
            .unwrap_or_default();
        report(
            &format!("window-activate: no window matched '{what}'"),
            options.stdout_report,
        );
        return std::process::ExitCode::from(1);
    };

    // Anchored so `class:^(org.telegram.desktop)$` cannot match a longer class.
    let selector = format!("class:^({})$", re_escape(target.app_id()));
    if let Err(exc) = hyprctl(&[
        "dispatch",
        &format!("hl.dsp.focus({{ window = {} }})", lua_string(&selector)),
    ]) {
        eprintln!("window-activate: {exc}");
        return std::process::ExitCode::from(2);
    }
    report(
        &format!(
            "window-activate: {} ({}, {})",
            if target.title.is_empty() {
                "?"
            } else {
                &target.title
            },
            target.app_id(),
            target.workspace
        ),
        options.stdout_report,
    );
    std::process::ExitCode::SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;

    fn window(class: &str, title: &str, workspace: &str, history: i64) -> Window {
        Window {
            class: class.to_string(),
            initial_class: class.to_string(),
            title: title.to_string(),
            workspace: workspace.to_string(),
            focus_history: history,
        }
    }

    #[test]
    fn classes_are_escaped_like_re_escape() {
        assert_eq!(
            re_escape("org.telegram.desktop"),
            "org\\.telegram\\.desktop"
        );
        assert_eq!(re_escape("kitty"), "kitty");
        assert_eq!(re_escape("a+b"), "a\\+b");
    }

    #[test]
    fn lua_strings_are_quoted_and_escaped() {
        assert_eq!(lua_string("a\"b\\c"), "\"a\\\"b\\\\c\"");
    }

    #[test]
    fn matching_covers_class_and_title() {
        let w = window(
            "org.telegram.desktop",
            "Telegram — Neg",
            "special:telegram",
            0,
        );
        assert!(matches(&w, Some("org.telegram.desktop"), None, false));
        assert!(!matches(&w, Some("org.telegram"), None, false));
        assert!(matches(&w, Some("telegram"), None, true));
        assert!(matches(&w, None, Some("neg"), false));
        assert!(!matches(&w, None, Some("slack"), false));
    }

    #[test]
    fn recency_prefers_the_lowest_focus_history() {
        let windows = vec![
            window("a", "", "1", 5),
            window("b", "", "2", 0),
            window("c", "", "3", 2),
        ];
        assert_eq!(by_recency(&windows).class, "b");
    }

    #[test]
    fn tray_ids_resolve_through_class_and_title() {
        let windows = vec![
            window("org.telegram.desktop", "Telegram", "special:telegram", 1),
            window("Nicotine", "Downloads", "2", 0),
        ];
        assert_eq!(
            pick_window(&windows, "TelegramDesktop", "Telegram").map(|w| w.class),
            Some("org.telegram.desktop".to_string())
        );
        assert_eq!(pick_window(&windows, "steam", "").map(|w| w.class), None);
        assert_eq!(pick_window(&windows, "", ""), None);
    }
}
