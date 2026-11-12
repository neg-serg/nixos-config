//! menu-search — search the tray apps' menus in a vicinae mini window.
//!
//! Every StatusNotifierItem publishes its context menu over DBusMenu; that tree
//! is exactly what a right-click on the tray icon shows, submenus included. The
//! local helper actions of `main-menu` are listed next to them, so one search
//! window covers both. Entries are rendered as `App › Path › Item`, fed to
//! `vicinae dmenu`, and the chosen one is triggered on the bus.
//!
//! A Qt app cannot raise its own window on Wayland (no `xdg-activation`), so an
//! entry whose label reads like "open/show" is backed up by a focus request
//! through `window-activate`, which can bring up even a hidden special
//! workspace. Labels meaning the opposite ("minimize", "quit") raise nothing.
//!
//! The entry list is cached in `$XDG_CACHE_HOME/menu-search/entries.tsv`; the
//! window is fed from the cache (the DBus walk costs ~0.75 s) and a detached
//! refresh updates the cache for the next invocation. A stale entry is retried
//! from a fresh walk before giving up.
//!
//! Port of `packages/local-bin/bin/menu-search`.

mod json;

use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const WATCHER: &str = "org.kde.StatusNotifierWatcher";
const WATCHER_PATH: &str = "/StatusNotifierWatcher";
const SNI_IFACE: &str = "org.kde.StatusNotifierItem";
const MENU_IFACE: &str = "com.canonical.dbusmenu";
const CACHE_VERSION: &str = "2";
const DEFAULT_OPEN_LABELS: [&str; 5] = ["open", "show", "открыть", "показать", "развернуть"];

extern "C" {
    fn flock(fd: i32, operation: i32) -> i32;
}
const LOCK_EX: i32 = 2;
const LOCK_NB: i32 = 4;

fn env_or(name: &str, fallback: &str) -> String {
    match std::env::var(name) {
        Ok(value) if !value.is_empty() => value,
        _ => fallback.to_string(),
    }
}

fn home() -> PathBuf {
    PathBuf::from(env_or("HOME", "/"))
}

fn which(program: &str) -> Option<PathBuf> {
    if program.contains('/') {
        let path = PathBuf::from(program);
        return path.is_file().then_some(path);
    }
    let path = std::env::var_os("PATH")?;
    std::env::split_paths(&path)
        .map(|dir| dir.join(program))
        .find(|candidate| candidate.is_file())
}

fn busctl_bin() -> Option<PathBuf> {
    match std::env::var("MENU_SEARCH_BUSCTL") {
        Ok(value) if !value.is_empty() => Some(PathBuf::from(value)),
        _ => which("busctl"),
    }
}

/// One flattened menu entry, kept in the order Python's dicts used so the JSON
/// dump stays byte-identical.
#[derive(Debug, Clone, PartialEq)]
pub struct Entry {
    pub fields: Vec<(String, json::Value)>,
}

impl Entry {
    fn new(fields: Vec<(&str, json::Value)>) -> Entry {
        Entry {
            fields: fields
                .into_iter()
                .map(|(key, value)| (key.to_string(), value))
                .collect(),
        }
    }

    pub fn get(&self, key: &str) -> Option<&json::Value> {
        self.fields
            .iter()
            .find(|(name, _)| name == key)
            .map(|(_, value)| value)
    }

    fn text(&self, key: &str) -> String {
        self.get(key)
            .and_then(json::Value::as_str)
            .unwrap_or("")
            .to_string()
    }

    fn kind(&self) -> String {
        match self.get("kind") {
            Some(value) => value.as_str().unwrap_or("menu").to_string(),
            None => "menu".to_string(),
        }
    }

    fn set(&mut self, key: &str, value: json::Value) {
        match self.fields.iter_mut().find(|(name, _)| name == key) {
            Some(entry) => entry.1 = value,
            None => self.fields.push((key.to_string(), value)),
        }
    }
}

// -- bus plumbing ------------------------------------------------------

fn busctl(args: &[&str], json_out: bool) -> Result<String, String> {
    let Some(binary) = busctl_bin() else {
        return Err("busctl not found".to_string());
    };
    let mut command = Command::new(binary);
    command.arg("--user");
    if json_out {
        command.arg("--json=short");
    }
    command
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let output = command.output().map_err(|exc| exc.to_string())?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        return Err(if stderr.is_empty() {
            format!("busctl {} failed", args.join(" "))
        } else {
            stderr
        });
    }
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

fn busctl_json(args: &[&str]) -> Result<json::Value, String> {
    let text = busctl(args, true)?;
    json::parse(&text).ok_or_else(|| "busctl returned invalid JSON".to_string())
}

/// The `data` payload of a busctl get-property/call answer.
fn property_data(value: &json::Value) -> Option<json::Value> {
    match value {
        json::Value::Object(_) => value.get("data").cloned(),
        _ => Some(value.clone()),
    }
}

fn property_of(service: &str, path: &str, iface: &str, name: &str) -> Option<json::Value> {
    let value = busctl_json(&["get-property", service, path, iface, name]).ok()?;
    property_data(&value)
}

/// Every registered item as `(service, object path)`.
fn tray_items() -> Vec<(String, String)> {
    let registered = property_of(
        WATCHER,
        WATCHER_PATH,
        WATCHER,
        "RegisteredStatusNotifierItems",
    )
    .unwrap_or(json::Value::Null);
    let Some(json::Value::Array(items)) = Some(registered) else {
        return Vec::new();
    };
    items
        .iter()
        .filter_map(|item| {
            let text = item.as_str()?;
            let (service, rest) = match text.split_once('/') {
                Some((service, rest)) => (service.to_string(), rest.to_string()),
                None => (text.to_string(), String::new()),
            };
            Some((
                service,
                if rest.is_empty() {
                    "/StatusNotifierItem".to_string()
                } else {
                    format!("/{rest}")
                },
            ))
        })
        .collect()
}

fn item_title(service: &str, path: &str) -> String {
    for property in ["Title", "Id"] {
        if let Some(value) = property_of(service, path, SNI_IFACE, property) {
            let text = match &value {
                json::Value::Str(text) => text.clone(),
                other => other.as_str().unwrap_or("").to_string(),
            };
            if !text.is_empty() {
                let text = if property == "Id" {
                    text.rsplit('.').next().unwrap_or(&text).to_string()
                } else {
                    text
                };
                if !text.is_empty() {
                    return text;
                }
            }
        }
    }
    service.to_string()
}

fn item_id(service: &str, path: &str) -> String {
    property_of(service, path, SNI_IFACE, "Id")
        .and_then(|value| value.as_str().map(str::to_string))
        .unwrap_or_default()
}

fn menu_path(service: &str, path: &str) -> Option<String> {
    if let Some(value) = property_of(service, path, SNI_IFACE, "Menu") {
        if let Some(text) = value.as_str() {
            if !text.is_empty() {
                return Some(text.to_string());
            }
        }
    }
    for guess in ["/MenuBar", "/StatusNotifierItem/menu"] {
        let call = busctl_json(&[
            "call",
            "--",
            service,
            guess,
            MENU_IFACE,
            "GetLayout",
            "iias",
            "0",
            "-1",
            "0",
        ]);
        if call.is_ok() {
            return Some(guess.to_string());
        }
    }
    None
}

/// A `{ "data": … }` wrapper from the DBusMenu variant encoding.
fn data_of(value: Option<&json::Value>) -> Option<json::Value> {
    let value = value?;
    value.get("data").cloned()
}

/// Flatten a DBusMenu layout tree into entries.
pub fn walk(children: &[json::Value], prefix: &[String], out: &mut Vec<Entry>) {
    for child in children {
        let entry = match child.get("data") {
            Some(inner) => inner.clone(),
            None => child.clone(),
        };
        let json::Value::Array(parts) = entry else {
            continue;
        };
        if parts.len() != 3 {
            continue;
        }
        let item_id = parts[0].clone();
        let props = match &parts[1] {
            json::Value::Object(_) => parts[1].clone(),
            _ => json::Value::Object(Vec::new()),
        };
        let sub = match &parts[2] {
            json::Value::Array(items) => items.clone(),
            _ => Vec::new(),
        };
        let kind_of = |name: &str| {
            data_of(props.get(name))
                .and_then(|value| value.as_str().map(str::to_string))
                .unwrap_or_default()
        };
        if kind_of("type") == "separator" {
            continue;
        }
        if let Some(visible) = data_of(props.get("visible")) {
            if matches!(visible, json::Value::Bool(false)) {
                continue;
            }
        }
        let label: String = kind_of("label")
            .replace('_', "")
            .replace('&', "")
            .trim()
            .to_string();
        let is_submenu = props.get("children-display").is_some() || !sub.is_empty();
        if is_submenu {
            let mut next = prefix.to_vec();
            if !label.is_empty() {
                next.push(label);
            }
            walk(&sub, &next, out);
            continue;
        }
        if label.is_empty() {
            continue;
        }
        let enabled = match data_of(props.get("enabled")) {
            Some(json::Value::Bool(false)) => false,
            _ => true,
        };
        out.push(Entry::new(vec![
            ("id", item_id.clone()),
            ("label", json::Value::Str(label)),
            (
                "path",
                json::Value::Array(
                    prefix
                        .iter()
                        .map(|item| json::Value::Str(item.clone()))
                        .collect(),
                ),
            ),
            ("enabled", json::Value::Bool(enabled)),
        ]));
    }
}

fn collect(service: &str, path: &str) -> Vec<Entry> {
    let Some(menu) = menu_path(service, path) else {
        return Vec::new();
    };
    let app_id = item_id(service, path);
    let Ok(layout) = busctl_json(&[
        "call",
        "--",
        service,
        &menu,
        MENU_IFACE,
        "GetLayout",
        "iias",
        "0",
        "-1",
        "0",
    ]) else {
        return Vec::new();
    };
    let children = layout
        .get("data")
        .and_then(|data| match data {
            json::Value::Array(items) => items.get(1),
            _ => None,
        })
        .and_then(|item| match item {
            json::Value::Array(items) => items.get(2),
            _ => None,
        })
        .and_then(|children| match children {
            json::Value::Array(items) => Some(items.clone()),
            _ => None,
        })
        .unwrap_or_default();
    let mut entries = Vec::new();
    walk(&children, &[], &mut entries);
    let app = item_title(service, path);
    for entry in &mut entries {
        entry.set("service", json::Value::Str(service.to_string()));
        entry.set("menu", json::Value::Str(menu.clone()));
        entry.set("app", json::Value::Str(app.clone()));
        entry.set("app_id", json::Value::Str(app_id.clone()));
    }
    entries
}

/// Click a DBusMenu item the way a mouse would.
fn trigger(entry: &Entry, dry_run: bool) -> bool {
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|delta| delta.as_secs())
        .unwrap_or(0);
    let id = match entry.get("id") {
        Some(json::Value::Number(number)) => format!("{}", *number as i64),
        Some(json::Value::Str(text)) => text.clone(),
        _ => String::new(),
    };
    let args = [
        "busctl",
        "--user",
        "call",
        "--",
        &entry.text("service"),
        &entry.text("menu"),
        MENU_IFACE,
        "Event",
        "isvu",
        &id,
        "clicked",
        "s",
        "",
        &stamp.to_string(),
    ];
    if dry_run {
        println!("{}", args.join(" "));
        return true;
    }
    let Some(binary) = busctl_bin() else {
        return false;
    };
    Command::new(binary)
        .args(args[1..].iter())
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

// -- the "app cannot focus itself" workaround --------------------------

fn window_activate_bin() -> Option<PathBuf> {
    if let Some(found) = which("window-activate") {
        return Some(found);
    }
    let fallback = home().join(".local/bin/window-activate");
    fallback.is_file().then_some(fallback)
}

fn main_menu_bin() -> Option<PathBuf> {
    if let Some(found) = which("main-menu") {
        return Some(found);
    }
    let fallback = home().join(".local/bin/main-menu");
    fallback.is_file().then_some(fallback)
}

/// The prefixes that promise "bring it up", asked from `window-activate` so the
/// two tools cannot drift.
fn open_labels() -> Vec<String> {
    if let Some(binary) = window_activate_bin() {
        if let Ok(output) = Command::new(binary)
            .arg("--open-prefix")
            .stdin(Stdio::null())
            .output()
        {
            if output.status.success() {
                let labels: Vec<String> = String::from_utf8_lossy(&output.stdout)
                    .lines()
                    .map(|line| line.trim().to_lowercase())
                    .filter(|line| !line.is_empty())
                    .collect();
                if !labels.is_empty() {
                    return labels;
                }
            }
        }
    }
    DEFAULT_OPEN_LABELS
        .iter()
        .map(|label| label.to_string())
        .collect()
}

/// Focus the window behind an "Open …" entry; `None` if nothing was raised.
fn raise_window_for(entry: &Entry) -> Option<String> {
    let label = entry.text("label").trim().to_lowercase();
    if !open_labels()
        .iter()
        .any(|prefix| label.starts_with(prefix.as_str()))
    {
        return None;
    }
    let binary = window_activate_bin()?;
    let mut tray_id = entry.text("app_id");
    if tray_id.is_empty() {
        tray_id = entry.text("app");
    }
    if tray_id.is_empty() {
        return None;
    }
    let mut command = Command::new(binary);
    command.args(["--raise-for", &tray_id]);
    let title = entry.text("app");
    if !title.is_empty() {
        command.args(["--tray-title", &title]);
    }
    let output = command.stdin(Stdio::null()).output().ok()?;
    if !output.status.success() {
        return None;
    }
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    Some(if stderr.is_empty() { tray_id } else { stderr })
}

/// The local helper actions (`main-menu --list`), searchable next to the menus.
fn action_entries() -> Vec<Entry> {
    let Some(binary) = main_menu_bin() else {
        return Vec::new();
    };
    let Ok(output) = Command::new(binary)
        .arg("--list")
        .stdin(Stdio::null())
        .output()
    else {
        return Vec::new();
    };
    if !output.status.success() {
        return Vec::new();
    }
    String::from_utf8_lossy(&output.stdout)
        .split_whitespace()
        .map(|name| {
            Entry::new(vec![
                ("kind", json::Value::Str("action".to_string())),
                ("id", json::Value::Str(name.to_string())),
                ("label", json::Value::Str(name.to_string())),
                ("path", json::Value::Array(Vec::new())),
                ("app", json::Value::Str("Actions".to_string())),
                ("action", json::Value::Str(name.to_string())),
                ("enabled", json::Value::Bool(true)),
                ("service", json::Value::Str(String::new())),
                ("menu", json::Value::Str(String::new())),
            ])
        })
        .collect()
}

fn run_action(entry: &Entry, dry_run: bool) -> bool {
    let Some(binary) = main_menu_bin() else {
        return false;
    };
    let action = entry.text("action");
    if dry_run {
        println!("{} --run {action}", binary.display());
        return true;
    }
    Command::new(binary)
        .args(["--run", &action])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

// -- the cache ---------------------------------------------------------

fn cache_dir() -> PathBuf {
    match std::env::var("XDG_CACHE_HOME") {
        Ok(value) if !value.is_empty() => PathBuf::from(value).join("menu-search"),
        _ => home().join(".cache").join("menu-search"),
    }
}

fn cache_path() -> PathBuf {
    cache_dir().join("entries.tsv")
}

/// The line shown for an entry; cached entries already carry it.
pub fn entry_line(entry: &Entry) -> String {
    if let Some(line) = entry.get("line").and_then(json::Value::as_str) {
        return line.to_string();
    }
    let mut parts: Vec<String> = vec![entry.text("app")];
    if let Some(json::Value::Array(path)) = entry.get("path") {
        parts.extend(
            path.iter()
                .filter_map(|item| item.as_str().map(str::to_string)),
        );
    }
    parts.push(entry.text("label"));
    parts.join(" › ")
}

pub fn load_cache(path: &Path) -> Vec<Entry> {
    let Ok(text) = std::fs::read_to_string(path) else {
        return Vec::new();
    };
    let mut entries = Vec::new();
    for line in text.lines() {
        let fields: Vec<&str> = line.split('\t').collect();
        if fields.len() != 8 || fields[0] != CACHE_VERSION {
            continue;
        }
        let (_, kind, service, menu, entry_id, action, app_id, display) = (
            fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6], fields[7],
        );
        let id = match entry_id.trim_start_matches('-').parse::<i64>() {
            Ok(number) if entry_id.chars().all(|ch| ch.is_ascii_digit() || ch == '-') => {
                json::Value::Number(number as f64)
            }
            _ => json::Value::Str(entry_id.to_string()),
        };
        entries.push(Entry::new(vec![
            ("kind", json::Value::Str(kind.to_string())),
            ("service", json::Value::Str(service.to_string())),
            ("menu", json::Value::Str(menu.to_string())),
            ("id", id),
            ("action", json::Value::Str(action.to_string())),
            ("app_id", json::Value::Str(app_id.to_string())),
            ("line", json::Value::Str(display.to_string())),
        ]));
    }
    entries
}

pub fn save_cache(path: &Path, entries: &[Entry]) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let tmp = path.with_extension("tmp");
    let mut body = String::new();
    for entry in entries {
        let id = match entry.get("id") {
            Some(json::Value::Number(number)) => format!("{}", *number as i64),
            Some(json::Value::Str(text)) => text.clone(),
            _ => String::new(),
        };
        body.push_str(&format!(
            "{CACHE_VERSION}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n",
            entry.kind(),
            entry.text("service"),
            entry.text("menu"),
            id,
            entry.text("action"),
            entry.text("app_id"),
            entry_line(entry)
        ));
    }
    std::fs::write(&tmp, body)?;
    std::fs::rename(&tmp, path)
}

fn enumerate_entries() -> Vec<Entry> {
    let mut entries = Vec::new();
    for (service, path) in tray_items() {
        entries.extend(collect(&service, &path));
    }
    entries.extend(action_entries());
    entries.sort_by_key(|entry| entry_line(entry));
    entries
}

/// Walk the menus and store the result; serialised with a non-blocking lock.
fn refresh_cache(program: &Path) -> i32 {
    let dir = cache_dir();
    if std::fs::create_dir_all(&dir).is_err() {
        return 1;
    }
    let lock_path = dir.join("refresh.lock");
    let Ok(lock) = std::fs::File::create(&lock_path) else {
        return 1;
    };
    use std::os::unix::io::AsRawFd;
    let locked = unsafe { flock(lock.as_raw_fd(), LOCK_EX | LOCK_NB) } == 0;
    if !locked {
        return 0; // someone else is already refreshing
    }
    let entries = enumerate_entries();
    if !entries.is_empty() {
        let _ = save_cache(&cache_path(), &entries);
    }
    let _ = program;
    0
}

fn main() -> std::process::ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let has = |flag: &str| args.iter().any(|arg| arg == flag);
    let value_of = |flag: &str| -> Option<String> {
        args.iter()
            .position(|arg| arg == flag)
            .and_then(|index| args.get(index + 1))
            .cloned()
    };

    if has("--refresh") {
        if busctl_bin().is_none() {
            eprintln!("menu-search: busctl not found");
            return std::process::ExitCode::from(1);
        }
        let program = std::env::current_exe().unwrap_or_else(|_| PathBuf::from("menu-search"));
        return std::process::ExitCode::from(refresh_cache(&program) as u8);
    }
    if busctl_bin().is_none() {
        eprintln!("menu-search: busctl not found");
        return std::process::ExitCode::from(1);
    }

    let entries = if has("--no-cache") {
        enumerate_entries()
    } else {
        let cached = load_cache(&cache_path());
        if cached.is_empty() {
            let fresh = enumerate_entries();
            if !fresh.is_empty() {
                let _ = save_cache(&cache_path(), &fresh);
            }
            fresh
        } else {
            cached
        }
    };

    if entries.is_empty() {
        eprintln!("menu-search: no menu entries found");
        return std::process::ExitCode::from(1);
    }

    if has("--json") {
        let rendered: Vec<json::Value> = entries
            .iter()
            .map(|entry| {
                let mut fields = entry.fields.clone();
                fields.push(("line".to_string(), json::Value::Str(entry_line(entry))));
                json::Value::Object(fields)
            })
            .collect();
        println!("{}", json::Value::Array(rendered).dump(Some(1)));
        return std::process::ExitCode::SUCCESS;
    }

    let vicinae = which("vicinae");
    if has("--list") || vicinae.is_none() {
        for entry in &entries {
            println!("{}", entry_line(entry));
        }
        if vicinae.is_none() {
            eprintln!("menu-search: vicinae not found, printed the entries instead");
        }
        return std::process::ExitCode::SUCCESS;
    }

    let lines: Vec<String> = entries.iter().map(entry_line).collect();
    let mut command = Command::new(vicinae.expect("checked above"));
    command.args([
        "dmenu",
        "-p",
        &value_of("--placeholder").unwrap_or_else(|| "Menus: ❯".to_string()),
        "-q",
        &value_of("--query").unwrap_or_default(),
        "-W",
        &value_of("--width").unwrap_or_else(|| "560".to_string()),
        "-H",
        &value_of("--height").unwrap_or_else(|| "420".to_string()),
    ]);
    if has("--print-trigger") {
        command.arg("--no-quick-look");
    }
    command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let Ok(mut child) = command.spawn() else {
        return std::process::ExitCode::SUCCESS;
    };
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(format!("{}\n", lines.join("\n")).as_bytes());
    }
    let Ok(output) = child.wait_with_output() else {
        return std::process::ExitCode::SUCCESS;
    };
    let chosen = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if !output.status.success() || chosen.is_empty() {
        return std::process::ExitCode::SUCCESS; // dismissed
    }
    let chosen = chosen.lines().last().unwrap_or("").to_string();
    let print_trigger = has("--print-trigger");
    let verbose = has("--verbose");

    let fire = |entry: &Entry| -> bool {
        if print_trigger {
            println!("chosen: {chosen}");
        }
        if entry.kind() == "action" {
            return run_action(entry, print_trigger);
        }
        let fired = trigger(entry, print_trigger);
        if fired && !print_trigger {
            if let Some(raised) = raise_window_for(entry) {
                if verbose {
                    eprintln!("menu-search: raised {raised}");
                }
            }
        }
        fired
    };
    let find = |source: &[Entry]| -> Option<Entry> {
        source
            .iter()
            .find(|entry| entry_line(entry) == chosen)
            .cloned()
    };

    if let Some(entry) = find(&entries) {
        if fire(&entry) {
            return std::process::ExitCode::SUCCESS;
        }
    }
    // The cached item may be gone (the app rebuilt its menu): walk once more.
    let fresh = enumerate_entries();
    if !fresh.is_empty() {
        let _ = save_cache(&cache_path(), &fresh);
    }
    if let Some(retry) = find(&fresh) {
        if fire(&retry) {
            return std::process::ExitCode::SUCCESS;
        }
        eprintln!("menu-search: '{chosen}' is no longer available");
        return std::process::ExitCode::from(1);
    }
    eprintln!("menu-search: '{chosen}' did not match an entry");
    std::process::ExitCode::from(1)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(text: &str) -> json::Value {
        json::parse(text).expect("json")
    }

    #[test]
    fn walks_nested_menus_and_skips_separators() {
        let layout = parse(
            r#"[0, [
                {"data": [10, {"label": {"data": "Open Telegram"}}, []]},
                {"data": [11, {"type": {"data": "separator"}}, []]},
                {"data": [12, {"label": {"data": "_Submenu"}}, [
                    {"data": [13, {"label": {"data": "Child & item"}}, []]}
                ]]},
                {"data": [14, {"label": {"data": "Hidden"}, "visible": {"data": false}}, []]},
                {"data": [15, {"label": {"data": ""}}, []]}
            ]]"#,
        );
        let json::Value::Array(items) = layout else {
            panic!("array")
        };
        let json::Value::Array(children) = &items[1] else {
            panic!("children")
        };
        let mut out = Vec::new();
        walk(children, &[], &mut out);
        assert_eq!(out.len(), 2);
        assert_eq!(out[0].text("label"), "Open Telegram");
        assert_eq!(entry_line(&out[0]), " › Open Telegram");
        // `&` is dropped, the spaces around it are not: `Child  item`.
        assert_eq!(out[1].text("label"), "Child  item");
        assert_eq!(entry_line(&out[1]), " › Submenu › Child  item");
    }

    #[test]
    fn cache_round_trips_through_tsv() {
        let dir = std::env::temp_dir().join(format!("menu-search-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("entries.tsv");
        let entries = vec![
            Entry::new(vec![
                ("kind", json::Value::Str("menu".to_string())),
                ("service", json::Value::Str(":1.42".to_string())),
                ("menu", json::Value::Str("/MenuBar".to_string())),
                ("id", json::Value::Number(10.0)),
                ("action", json::Value::Str(String::new())),
                ("app_id", json::Value::Str("TelegramDesktop".to_string())),
                ("line", json::Value::Str("Telegram › Open".to_string())),
            ]),
            Entry::new(vec![
                ("kind", json::Value::Str("action".to_string())),
                ("service", json::Value::Str(String::new())),
                ("menu", json::Value::Str(String::new())),
                ("id", json::Value::Str("music".to_string())),
                ("action", json::Value::Str("music".to_string())),
                ("app_id", json::Value::Str(String::new())),
                ("line", json::Value::Str("Actions › music".to_string())),
            ]),
        ];
        save_cache(&path, &entries).expect("save");
        let loaded = load_cache(&path);
        assert_eq!(loaded.len(), 2);
        assert_eq!(entry_line(&loaded[0]), "Telegram › Open");
        assert!(
            matches!(loaded[0].get("id"), Some(json::Value::Number(number)) if *number == 10.0)
        );
        assert_eq!(loaded[1].text("action"), "music");
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn broken_cache_lines_are_skipped() {
        let dir = std::env::temp_dir().join(format!("menu-search-bad-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("entries.tsv");
        std::fs::write(
            &path,
            "1\tmenu\ta\tb\t1\t\t\tline\n2\tmenu\ta\tb\t1\t\t\tok\n",
        )
        .unwrap();
        assert_eq!(load_cache(&path).len(), 1);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn entry_lines_join_app_path_and_label() {
        let entry = Entry::new(vec![
            ("app", json::Value::Str("Telegram".to_string())),
            (
                "path",
                json::Value::Array(vec![
                    json::Value::Str("Settings".to_string()),
                    json::Value::Str("Audio".to_string()),
                ]),
            ),
            ("label", json::Value::Str("Volume".to_string())),
        ]);
        assert_eq!(entry_line(&entry), "Telegram › Settings › Audio › Volume");
    }
}
