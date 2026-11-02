//! Pill bot: the Telegram side of the pill reminder.
//!
//! Long-polls `getUpdates` and turns presses of the "Mark taken" button into a
//! confirmation: the panel's pill state and the vdirsyncer calendar event are
//! written first, then the reminder message is edited in place. It is also a
//! bridge in the other direction — a mark (or unmark) done in the panel edits
//! the very same Telegram message, restoring the button when the dose is
//! unmarked, so the pill can be confirmed from either side.
//!
//! Configuration comes from the environment:
//!   PILL_BOT_TOKEN_PATH        decrypted bot token (root, 0400)
//!   PILL_BOT_CHAT_ID_PATH      decrypted chat id (root, 0400)
//!   PILL_BOT_STATE_DIR         offset + pill log (default /var/lib/telegram-pill-bot)
//!   PILL_BOT_LAST_MESSAGE      reminder message record
//!   PILL_BOT_PANEL_STATE       panel state written for the desktop user
//!   PILL_BOT_PANEL_STATE_LEGACY  pre-rename state, read while the new one is absent
//!   PILL_BOT_ICS_DIR           vdirsyncer collection for the "taken" events
//!   PILL_BOT_OWNER             desktop user owning those files
//!   PILL_BOT_CURL, PILL_BOT_PROXY, PILL_BOT_API_BASE
//!   PILL_BOT_ONCE=1            process one poll batch and exit (tests)
//!   PILL_BOT_SLEEP             pause between iterations, seconds (default 5)
//!   PILL_BOT_IDLE_TIMEOUT      getUpdates long-poll timeout (default 25)

#[path = "lib.rs"]
mod shared;

use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use shared::json::Value;

const DEFAULT_CURL: &str = "/run/current-system/sw/bin/curl";
const DEFAULT_PROXY: &str = "socks5h://127.0.0.1:10808";
const DEFAULT_API_BASE: &str = "https://api.telegram.org";
const DEFAULT_STATE_DIR: &str = "/var/lib/telegram-pill-bot";
const DEFAULT_LAST_MESSAGE: &str = "/var/lib/telegram-pill-reminder/last-message.json";
/// Must match `telegram-pill-reminder`: used to restore the message with its
/// button when the panel mark is reverted.
const REMINDER_TEXT: &str = "💊 12:00 — time to take your pill. Tap «Mark taken» once you have.";
const REMINDER_MARKUP: &str =
    r#"{"inline_keyboard": [[{"text": "Mark taken \u2705", "callback_data": "pill_taken"}]]}"#;
const CONFIRMED_TEXT: &str = "💊 Taken ✅ ({0})";

extern "C" {
    fn chown(path: *const u8, owner: u32, group: u32) -> i32;
    fn chmod(path: *const u8, mode: u32) -> i32;
}

fn env_or(name: &str, fallback: &str) -> String {
    match std::env::var(name) {
        Ok(value) if !value.is_empty() => value,
        _ => fallback.to_string(),
    }
}

fn path_or(name: &str, fallback: &str) -> PathBuf {
    PathBuf::from(env_or(name, fallback))
}

fn once_mode() -> bool {
    matches!(std::env::var("PILL_BOT_ONCE"), Ok(value) if !value.is_empty() && value != "0")
}

fn sleep_seconds() -> u64 {
    env_or("PILL_BOT_SLEEP", "5").trim().parse().unwrap_or(5)
}

fn read_secret(path: &Path) -> Option<String> {
    std::fs::read_to_string(path)
        .ok()
        .map(|text| text.trim().to_string())
        .filter(|text| !text.is_empty())
}

// -- time --------------------------------------------------------------

/// Local time in `strftime` terms, through coreutils `date` (the bot runs in a
/// systemd unit where `date` is on the system path).
fn date_arg(format: &str) -> String {
    for candidate in ["/run/current-system/sw/bin/date", "date"] {
        if let Ok(output) = Command::new(candidate).arg(format).output() {
            if output.status.success() {
                return String::from_utf8_lossy(&output.stdout).trim().to_string();
            }
        }
    }
    String::new()
}

/// `YYYY-MM-DD HH:MM TZ`, the stamp written into the pill log.
fn stamp_now() -> String {
    let stamp = date_arg("+%Y-%m-%d %H:%M %Z");
    if stamp.is_empty() {
        date_arg("+%Y-%m-%d %H:%M")
    } else {
        stamp
    }
}

fn today() -> String {
    let value = date_arg("+%Y-%m-%d");
    if value.is_empty() {
        shared::local_today()
    } else {
        value
    }
}

fn clock_now() -> String {
    date_arg("+%H:%M")
}

// -- API ---------------------------------------------------------------

struct Api {
    curl: String,
    proxy: String,
    token: String,
    base: String,
}

impl Api {
    fn new(token: String) -> Api {
        Api {
            curl: env_or("PILL_BOT_CURL", DEFAULT_CURL),
            proxy: env_or("PILL_BOT_PROXY", DEFAULT_PROXY),
            token,
            base: env_or("PILL_BOT_API_BASE", DEFAULT_API_BASE),
        }
    }

    /// One Bot API call; returns stdout when curl exits 0.
    fn call(&self, method: &str, params: &[(&str, String)]) -> Option<String> {
        let url = format!("{}/bot{}/{}", self.base, self.token, method);
        let mut command = Command::new(&self.curl);
        command.args(["-s", "--proxy", &self.proxy, "--max-time", "70", "-K", "-"]);
        for (key, value) in params {
            command.args(["--data-urlencode", &format!("{key}={value}")]);
        }
        command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        let mut child = command.spawn().ok()?;
        if let Some(mut stdin) = child.stdin.take() {
            let _ = stdin.write_all(shared::curl_url_config(&url).as_bytes());
        }
        let output = child.wait_with_output().ok()?;
        if !output.status.success() {
            return None;
        }
        Some(String::from_utf8_lossy(&output.stdout).to_string())
    }
}

// -- panel state -------------------------------------------------------

fn owner_ids(owner: &str) -> Option<(u32, u32)> {
    let uid = Command::new("id")
        .args(["-u", owner])
        .output()
        .ok()
        .and_then(|out| String::from_utf8_lossy(&out.stdout).trim().parse().ok())?;
    let gid = Command::new("id")
        .args(["-g", owner])
        .output()
        .ok()
        .and_then(|out| String::from_utf8_lossy(&out.stdout).trim().parse().ok())?;
    Some((uid, gid))
}

fn c_path(path: &Path) -> Vec<u8> {
    let mut bytes = path.as_os_str().as_encoded_bytes().to_vec();
    bytes.push(0);
    bytes
}

/// Hand a file to the desktop user with mode 0644.
fn give_file_to_owner(path: &Path, ids: Option<(u32, u32)>) {
    let Some((uid, gid)) = ids else { return };
    let bytes = c_path(path);
    unsafe {
        chown(bytes.as_ptr(), uid, gid);
        chmod(bytes.as_ptr(), 0o644);
    }
}

/// Directories keep their mode (0755): a 0644 collection dir would not be
/// traversable, which is exactly what vdirsyncer needs.
fn give_dir_to_owner(path: &Path, ids: Option<(u32, u32)>) {
    let Some((uid, gid)) = ids else { return };
    let bytes = c_path(path);
    unsafe {
        chown(bytes.as_ptr(), uid, gid);
    }
}

fn panel_state_path() -> PathBuf {
    let current = path_or("PILL_BOT_PANEL_STATE", "");
    if !current.as_os_str().is_empty() && current.exists() {
        return current;
    }
    let legacy = path_or("PILL_BOT_PANEL_STATE_LEGACY", "/dev/null");
    if legacy.exists() {
        return legacy;
    }
    current
}

pub fn read_panel_state(path: &Path) -> Value {
    std::fs::read_to_string(path)
        .ok()
        .and_then(|text| shared::json::parse(&text))
        .filter(|value| matches!(value, Value::Object(_)))
        .unwrap_or(Value::Object(Vec::new()))
}

fn write_panel_state(path: &Path, state: &Value, ids: Option<(u32, u32)>) {
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let _ = std::fs::write(path, format!("{}\n", state.dump(Some(4))));
    give_file_to_owner(path, ids);
}

/// Record today's dose in the panel state and in the calendar.
pub fn mark_panel_taken(
    panel_state: &Path,
    ics_dir: &Path,
    ids: Option<(u32, u32)>,
    today: &str,
    taken_at: &str,
) {
    let mut state = read_panel_state(panel_state);
    if let Value::Object(entries) = &mut state {
        set(entries, "todayDate", Value::Str(today.to_string()));
        set(entries, "taken", Value::Bool(true));
        set(entries, "takenAt", Value::Str(taken_at.to_string()));
        let has_history = entries
            .iter()
            .find(|(name, _)| name == "history")
            .map(|(_, value)| matches!(value, Value::Array(_)))
            .unwrap_or(false);
        if !has_history {
            set(entries, "history", Value::Array(Vec::new()));
        }
    }
    write_panel_state(panel_state, &state, ids);
    write_panel_ics(ics_dir, ids, today, taken_at);
}

fn set(entries: &mut Vec<(String, Value)>, key: &str, value: Value) {
    match entries.iter_mut().find(|(name, _)| name == key) {
        Some(entry) => entry.1 = value,
        None => entries.push((key.to_string(), value)),
    }
}

fn get<'a>(entries: &'a [(String, Value)], key: &str) -> Option<&'a Value> {
    entries
        .iter()
        .find(|(name, _)| name == key)
        .map(|(_, value)| value)
}

pub fn write_panel_ics(ics_dir: &Path, ids: Option<(u32, u32)>, today: &str, taken_at: &str) {
    let _ = std::fs::create_dir_all(ics_dir);
    let compact: String = today.chars().filter(|ch| *ch != '-').collect();
    let ics = [
        "BEGIN:VCALENDAR".to_string(),
        "VERSION:2.0".to_string(),
        "PRODID:-//Neg//PillTracker//EN".to_string(),
        "BEGIN:VEVENT".to_string(),
        format!("DTSTART;VALUE=DATE:{compact}"),
        format!("DTEND;VALUE=DATE:{compact}"),
        "SUMMARY:Pill ✅".to_string(),
        format!("DESCRIPTION:Taken at {taken_at}"),
        "CATEGORIES:Health".to_string(),
        "END:VEVENT".to_string(),
        "END:VCALENDAR".to_string(),
        String::new(),
    ];
    let path = ics_dir.join(format!("pill-{today}.ics"));
    let _ = std::fs::write(&path, ics.join("\r\n"));
    give_file_to_owner(&path, ids);
    // The collection dir may have just been created as root; hand it back
    // (ownership only) so vdirsyncer stays writable.
    give_dir_to_owner(ics_dir, ids);
}

pub fn remove_panel_ics(ics_dir: &Path, today: &str) {
    let _ = std::fs::remove_file(ics_dir.join(format!("pill-{today}.ics")));
}

// -- reminder message record -------------------------------------------

fn last_message_path() -> PathBuf {
    path_or("PILL_BOT_LAST_MESSAGE", DEFAULT_LAST_MESSAGE)
}

/// The day's reminder message record, when it belongs to `today`.
pub fn last_message(path: &Path, today: &str) -> Option<Value> {
    let value = std::fs::read_to_string(path)
        .ok()
        .and_then(|text| shared::json::parse(&text))?;
    let Value::Object(entries) = &value else {
        return None;
    };
    match get(entries, "date") {
        Some(Value::Str(date)) if date == today => {}
        _ => return None,
    }
    let mut value = value;
    if let Value::Object(entries) = &mut value {
        if get(entries, "confirmed").is_none() {
            set(entries, "confirmed", Value::Bool(false));
        }
    }
    Some(value)
}

fn save_last_message(path: &Path, value: &Value) {
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let _ = std::fs::write(path, value.dump(None));
}

fn log_line(path: &Path, text: &str) {
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    if let Ok(mut file) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
    {
        let _ = writeln!(file, "{text}");
    }
}

fn message_id(value: &Value) -> Option<i64> {
    match value {
        Value::Object(entries) => get(entries, "message_id").and_then(Value::as_i64),
        _ => None,
    }
}

fn chat_id_of(value: &Value) -> Option<String> {
    match value {
        Value::Object(entries) => get(entries, "chat_id").map(|value| match value {
            Value::Number(number) => format!("{}", *number as i64),
            Value::Str(text) => text.clone(),
            _ => String::new(),
        }),
        _ => None,
    }
}

fn edit_message(
    api: &Api,
    chat_id: &str,
    message_id: i64,
    text: &str,
    markup: Option<&str>,
) -> bool {
    let mut params = vec![
        ("chat_id", chat_id.to_string()),
        ("message_id", message_id.to_string()),
        ("text", text.to_string()),
    ];
    if let Some(markup) = markup {
        params.push(("reply_markup", markup.to_string()));
    }
    api.call("editMessageText", &params).is_some()
}

/// Converge the day's Telegram message on the panel state.
fn sync_from_panel(api: &Api, today: &str) {
    let record_path = last_message_path();
    let Some(mut record) = last_message(&record_path, today) else {
        return;
    };
    let panel = read_panel_state(&panel_state_path());
    let taken = match &panel {
        Value::Object(entries) => {
            matches!(get(entries, "todayDate"), Some(Value::Str(date)) if date == today)
                && matches!(get(entries, "taken"), Some(Value::Bool(true)))
        }
        _ => false,
    };
    let confirmed = matches!(&record, Value::Object(entries) if matches!(get(entries, "confirmed"), Some(Value::Bool(true))));
    if confirmed == taken {
        return;
    }
    let (Some(chat_id), Some(message_id)) = (chat_id_of(&record), message_id(&record)) else {
        return;
    };
    let ok = if taken {
        let taken_at = match &panel {
            Value::Object(entries) => match get(entries, "takenAt") {
                Some(Value::Str(text)) if !text.is_empty() => text.clone(),
                _ => clock_now(),
            },
            _ => clock_now(),
        };
        edit_message(
            api,
            &chat_id,
            message_id,
            &CONFIRMED_TEXT.replace("{0}", &format!("{today} {taken_at}")),
            None,
        )
    } else {
        edit_message(
            api,
            &chat_id,
            message_id,
            REMINDER_TEXT,
            Some(REMINDER_MARKUP),
        )
    };
    if ok {
        if let Value::Object(entries) = &mut record {
            set(entries, "confirmed", Value::Bool(taken));
        }
        save_last_message(&record_path, &record);
        if taken {
            log_line(&state_dir().join("pill-log.txt"), &stamp_now());
        }
    }
}

fn state_dir() -> PathBuf {
    path_or("PILL_BOT_STATE_DIR", DEFAULT_STATE_DIR)
}

fn read_offset() -> i64 {
    std::fs::read_to_string(state_dir().join("offset"))
        .ok()
        .and_then(|text| text.trim().parse().ok())
        .unwrap_or(0)
}

fn write_offset(offset: i64) {
    let dir = state_dir();
    let _ = std::fs::create_dir_all(&dir);
    let _ = std::fs::write(dir.join("offset"), offset.to_string());
}

// -- main --------------------------------------------------------------

fn handle_update(update: &Value, api: &Api, chat_id: &str, today: &str) {
    let Value::Object(entries) = update else {
        return;
    };
    let callback = get(entries, "callback_query");
    let message = get(entries, "message");
    if callback.is_none() {
        // Log who talks to the bot so the owner id can be captured.
        if let Some(Value::Object(message)) = message {
            let sender = message
                .iter()
                .find(|(name, _)| name == "from")
                .map(|(_, value)| value);
            let chat = get(message, "chat");
            let id = |value: Option<&Value>, key: &str| match value {
                Some(Value::Object(entries)) => match get(entries, key) {
                    Some(Value::Number(number)) => format!("{}", *number as i64),
                    Some(Value::Str(text)) => text.clone(),
                    _ => "(none)".to_string(),
                },
                _ => "(none)".to_string(),
            };
            eprintln!(
                "pill-bot: message from {} in chat {} (type {})",
                id(sender, "id"),
                id(chat, "id"),
                id(chat, "type")
            );
        }
    }
    let Some(Value::Object(callback)) = callback else {
        return;
    };
    // Private-chat bot: only presses from the owner count. In a 1:1 chat both
    // chat.id and from.id equal the user id, which is the chat the reminders go
    // to, so anything else is ignored.
    let cb_message = get(callback, "message");
    let cb_chat_id = match cb_message {
        Some(Value::Object(entries)) => match get(entries, "chat") {
            Some(Value::Object(chat)) => match get(chat, "id") {
                Some(Value::Number(number)) => format!("{}", *number as i64),
                Some(Value::Str(text)) => text.clone(),
                _ => String::new(),
            },
            _ => String::new(),
        },
        _ => String::new(),
    };
    let from_id = match get(callback, "from") {
        Some(Value::Object(from)) => match get(from, "id") {
            Some(Value::Number(number)) => format!("{}", *number as i64),
            Some(Value::Str(text)) => text.clone(),
            _ => String::new(),
        },
        _ => String::new(),
    };
    if cb_chat_id != chat_id || from_id != chat_id {
        return;
    }
    let query_id = match get(callback, "id") {
        Some(Value::Str(text)) => text.clone(),
        _ => String::new(),
    };
    let data_field = match get(callback, "data") {
        Some(Value::Str(text)) => text.clone(),
        _ => String::new(),
    };
    let _ = api.call("answerCallbackQuery", &[("callback_query_id", query_id)]);
    if data_field != "pill_taken" {
        return;
    }
    let Some(message_id_value) = cb_message.and_then(|value| match value {
        Value::Object(entries) => get(entries, "message_id").and_then(Value::as_i64),
        _ => None,
    }) else {
        return;
    };
    let taken_at = stamp_now();
    // Record in the panel first: the capsule lights up and the day is marked in
    // the calendar. If the Telegram edit fails, sync_from_panel heals it.
    mark_panel_taken(
        &panel_state_path(),
        &path_or("PILL_BOT_ICS_DIR", "/tmp/pill-ics"),
        owner_ids(&env_or("PILL_BOT_OWNER", "neg")),
        today,
        &clock_now(),
    );
    let _ = api.call(
        "editMessageText",
        &[
            ("chat_id", cb_chat_id.clone()),
            ("message_id", message_id_value.to_string()),
            ("text", CONFIRMED_TEXT.replace("{0}", &taken_at)),
        ],
    );
    let record_path = last_message_path();
    let mut record = last_message(&record_path, today).unwrap_or(Value::Object(vec![
        ("date".to_string(), Value::Str(today.to_string())),
        ("chat_id".to_string(), Value::Str(cb_chat_id.clone())),
        (
            "message_id".to_string(),
            Value::Number(message_id_value as f64),
        ),
    ]));
    if message_id(&record) == Some(message_id_value) {
        if let Value::Object(entries) = &mut record {
            set(entries, "confirmed", Value::Bool(true));
        }
        save_last_message(&record_path, &record);
    }
    log_line(&state_dir().join("pill-log.txt"), &taken_at);
}

fn main() -> std::process::ExitCode {
    let once = once_mode();
    loop {
        let today = today();
        let token_path = path_or("PILL_BOT_TOKEN_PATH", "");
        let chat_id_path = path_or("PILL_BOT_CHAT_ID_PATH", "");
        let (Some(token), Some(chat_id)) = (read_secret(&token_path), read_secret(&chat_id_path))
        else {
            eprintln!("pill-bot: cannot read the bot token or the chat id");
            if once {
                return std::process::ExitCode::from(1);
            }
            std::thread::sleep(std::time::Duration::from_secs(sleep_seconds()));
            continue;
        };
        let api = Api::new(token);

        // Bridge: panel-side marks edit the Telegram message and Telegram-side
        // marks update the panel capsule/calendar; converging on the recorded
        // confirmation also heals half-applied state.
        sync_from_panel(&api, &today);

        let offset = read_offset();
        let timeout = env_or("PILL_BOT_IDLE_TIMEOUT", "25");
        let response = api.call(
            "getUpdates",
            &[("offset", (offset + 1).to_string()), ("timeout", timeout)],
        );
        let Some(response) = response else {
            if once {
                return std::process::ExitCode::SUCCESS;
            }
            std::thread::sleep(std::time::Duration::from_secs(sleep_seconds()));
            continue;
        };
        let Some(parsed) = shared::json::parse(&response) else {
            if once {
                return std::process::ExitCode::SUCCESS;
            }
            std::thread::sleep(std::time::Duration::from_secs(sleep_seconds()));
            continue;
        };
        let ok = matches!(parsed.get("ok"), Some(Value::Bool(true)));
        if !ok {
            if once {
                return std::process::ExitCode::SUCCESS;
            }
            std::thread::sleep(std::time::Duration::from_secs(sleep_seconds()));
            continue;
        }
        let mut offset = offset;
        let mut handled = 0usize;
        if let Some(Value::Array(updates)) = parsed.get("result") {
            for update in updates {
                if let Value::Object(entries) = update {
                    if let Some(id) = get(entries, "update_id").and_then(Value::as_i64) {
                        offset = offset.max(id);
                    }
                }
                handle_update(update, &api, &chat_id, &today);
                handled += 1;
            }
        }
        write_offset(offset);
        if once || handled == 0 && once {
            return std::process::ExitCode::SUCCESS;
        }
        if once {
            return std::process::ExitCode::SUCCESS;
        }
        std::thread::sleep(std::time::Duration::from_millis(200));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "pill-bot-{tag}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|delta| delta.as_nanos())
                .unwrap_or(0)
        ));
        std::fs::create_dir_all(&dir).expect("temp dir");
        dir
    }

    #[test]
    fn taken_marks_the_panel_state_and_the_calendar() {
        let dir = temp_dir("mark");
        let state = dir.join("panel.json");
        std::fs::write(&state, r#"{"history": ["old"]}"#).unwrap();
        let ics = dir.join("ics");
        mark_panel_taken(&state, &ics, None, "2026-11-02", "12:04");
        let written = std::fs::read_to_string(&state).unwrap();
        assert!(
            written.contains("\"todayDate\": \"2026-11-02\""),
            "{written}"
        );
        assert!(written.contains("\"taken\": true"), "{written}");
        assert!(written.contains("\"takenAt\": \"12:04\""), "{written}");
        assert!(written.ends_with("}\n"), "{written}");
        let event = std::fs::read_to_string(ics.join("pill-2026-11-02.ics")).unwrap();
        assert!(event.contains("DTSTART;VALUE=DATE:20261102"), "{event}");
        assert!(event.contains("SUMMARY:Pill \u{2705}"), "{event}");
        assert!(event.contains("END:VCALENDAR\r\n"), "{event}");
        remove_panel_ics(&ics, "2026-11-02");
        assert!(!ics.join("pill-2026-11-02.ics").exists());
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn last_message_only_belongs_to_today() {
        let dir = temp_dir("record");
        let path = dir.join("last-message.json");
        std::fs::write(
            &path,
            r#"{"date": "2026-11-02", "chat_id": 1, "message_id": 7}"#,
        )
        .unwrap();
        let record = last_message(&path, "2026-11-02").expect("record");
        assert!(matches!(record.get("confirmed"), Some(Value::Bool(false))));
        assert!(last_message(&path, "2026-11-03").is_none());
        std::fs::write(&path, "not json").unwrap();
        assert!(last_message(&path, "2026-11-02").is_none());
        std::fs::remove_dir_all(&dir).ok();
    }
}
