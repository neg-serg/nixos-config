//! Daily pill reminder for Telegram.
//!
//! Sends one message a day with an inline "Mark taken" button. It stays quiet
//! when the panel already recorded today's dose, and a dated marker file keeps
//! snapshot restores or late boot catch-ups from sending twice. The message id
//! is remembered so `telegram-pill-bot` can edit the very same message once the
//! dose is marked from either side.
//!
//! Paths come from the environment (the unit sets them), which keeps the binary
//! free of build-time substitution and makes the whole flow testable:
//!   PILL_PANEL_STATE         panel state file (quickshell pill capsule)
//!   PILL_PANEL_LEGACY_STATE  pre-rename state file, read while the new one is absent
//!   PILL_BOT_TOKEN_PATH      decrypted bot token (root, 0400)
//!   PILL_CHAT_ID_PATH        decrypted chat id (root, 0400)
//!   PILL_STATE_DIR           where the marker and the sent-message record live
//!   PILL_CURL                curl binary (default the system one)
//!   PILL_PROXY               socks proxy for the Bot API
//!   PILL_ATTEMPTS, PILL_PAUSE  retry policy (default 12 attempts, 5s apart)

#[path = "lib.rs"]
mod shared;

use std::path::{Path, PathBuf};

const DEFAULT_CURL: &str = "/run/current-system/sw/bin/curl";
const DEFAULT_PROXY: &str = "socks5h://127.0.0.1:10808";
const DEFAULT_STATE_DIR: &str = "/var/lib/telegram-pill-reminder";
const TEXT: &str = "💊 12:00 — time to take your pill. Tap «Mark taken» once you have.";
/// `json.dumps` with its default `ensure_ascii=True` escapes non-ASCII, so the
/// markup keeps the `\u2705` form the Python reminder sent (same JSON, same
/// bytes on the wire).
fn markup() -> String {
    let template =
        r#"{"inline_keyboard": [[{"text": "Mark taken ✅", "callback_data": "pill_taken"}]]}"#;
    let mut out = String::with_capacity(template.len() + 8);
    for ch in template.chars() {
        if (ch as u32) < 0x7f {
            out.push(ch);
        } else {
            out.push_str(&format!("\\u{:04x}", ch as u32));
        }
    }
    out
}

fn env_or(name: &str, fallback: &str) -> String {
    match std::env::var(name) {
        Ok(value) if !value.is_empty() => value,
        _ => fallback.to_string(),
    }
}

fn panel_state_file() -> PathBuf {
    let current = std::env::var("PILL_PANEL_STATE").map(PathBuf::from).ok();
    if let Some(current) = current.filter(|path| path.exists()) {
        return current;
    }
    std::env::var("PILL_PANEL_LEGACY_STATE")
        .map(PathBuf::from)
        .unwrap_or_default()
}

/// True when the panel already recorded a dose for `today`.
pub fn already_taken_today(panel_state: &Path, today: &str) -> bool {
    let Ok(text) = std::fs::read_to_string(panel_state) else {
        return false;
    };
    let Some(shared::json::Value::Object(_)) = shared::json::parse(&text) else {
        return false;
    };
    let parsed = shared::json::parse(&text).expect("parsed above");
    let date_ok = parsed
        .get("todayDate")
        .and_then(shared::json::Value::as_str)
        .map(|value| value == today)
        .unwrap_or(false);
    let taken = parsed
        .get("taken")
        .and_then(shared::json::Value::as_bool)
        .unwrap_or(false);
    date_ok && taken
}

fn marker_says_sent(marker: &Path, today: &str) -> bool {
    match std::fs::read_to_string(marker) {
        Ok(text) => text.trim() == today,
        Err(_) => false,
    }
}

fn read_secret(path: &str) -> Option<String> {
    std::fs::read_to_string(path)
        .ok()
        .map(|text| text.trim().to_string())
        .filter(|text| !text.is_empty())
}

fn main() -> std::process::ExitCode {
    let today = shared::local_today();
    let state_dir = PathBuf::from(env_or("PILL_STATE_DIR", DEFAULT_STATE_DIR));
    let marker = state_dir.join("last-sent.txt");
    let last_message = state_dir.join("last-message.json");

    let panel_state = panel_state_file();
    if already_taken_today(&panel_state, &today) {
        println!("pill-reminder: pill already taken today, skipping");
        return std::process::ExitCode::SUCCESS;
    }
    if marker_says_sent(&marker, &today) {
        println!("pill-reminder: already sent today, skipping");
        return std::process::ExitCode::SUCCESS;
    }

    let token_path = env_or("PILL_BOT_TOKEN_PATH", "");
    let chat_id_path = env_or("PILL_CHAT_ID_PATH", "");
    let (Some(token), Some(chat_id)) = (read_secret(&token_path), read_secret(&chat_id_path))
    else {
        eprintln!("pill-reminder: cannot read the bot token or the chat id");
        return std::process::ExitCode::from(1);
    };

    let curl = env_or("PILL_CURL", DEFAULT_CURL);
    let proxy = env_or("PILL_PROXY", DEFAULT_PROXY);
    let attempts = env_or("PILL_ATTEMPTS", "12").parse().unwrap_or(12);
    let pause = env_or("PILL_PAUSE", "5").parse().unwrap_or(5);

    let markup_value = markup();
    let post = shared::CurlPost {
        curl: &curl,
        token: &token,
        chat_id: &chat_id,
        text: TEXT,
        reply_markup: Some(&markup_value),
        proxy: if proxy == "off" { None } else { Some(&proxy) },
        attempts,
        pause_seconds: pause,
    };
    match post.send() {
        Ok(body) => {
            if let Err(exc) = std::fs::create_dir_all(&state_dir) {
                eprintln!(
                    "pill-reminder: cannot create {}: {exc}",
                    state_dir.display()
                );
            }
            let _ = std::fs::write(&marker, &today);
            record_sent_message(&last_message, &body, &chat_id, &today);
            std::process::ExitCode::SUCCESS
        }
        Err(exc) => {
            eprintln!("pill-reminder: {exc}");
            std::process::ExitCode::from(1)
        }
    }
}

/// Remember the sent message so a later "taken" can edit the same message.
fn record_sent_message(path: &Path, body: &str, chat_id: &str, today: &str) {
    let Some(shared::json::Value::Object(_)) = shared::json::parse(body) else {
        eprintln!("pill-reminder: could not record sent message id");
        return;
    };
    let parsed = shared::json::parse(body).expect("parsed above");
    let message_id = parsed
        .get("result")
        .and_then(|result| result.get("message_id"))
        .and_then(shared::json::Value::as_i64);
    let Some(message_id) = message_id else {
        return;
    };
    let record = format!(
        "{{\"date\": \"{today}\", \"chat_id\": \"{}\", \"message_id\": {message_id}, \"confirmed\": false}}",
        chat_id.replace('\\', "\\\\").replace('"', "\\\"")
    );
    if let Err(exc) = std::fs::write(path, record) {
        eprintln!("pill-reminder: could not record sent message id: {exc}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "pill-{tag}-{}-{}",
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
    fn panel_state_needs_todays_date_and_taken() {
        let dir = temp_dir("panel");
        let state = dir.join("panel.json");
        std::fs::write(&state, r#"{"todayDate": "2026-11-02", "taken": true}"#).unwrap();
        assert!(already_taken_today(&state, "2026-11-02"));
        assert!(!already_taken_today(&state, "2026-11-03"));
        std::fs::write(&state, r#"{"todayDate": "2026-11-02", "taken": false}"#).unwrap();
        assert!(!already_taken_today(&state, "2026-11-02"));
        std::fs::write(&state, "not json").unwrap();
        assert!(!already_taken_today(&state, "2026-11-02"));
        assert!(!already_taken_today(
            &dir.join("missing.json"),
            "2026-11-02"
        ));
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn marker_matches_only_the_current_day() {
        let dir = temp_dir("marker");
        let marker = dir.join("last-sent.txt");
        assert!(!marker_says_sent(&marker, "2026-11-02"));
        std::fs::write(&marker, "2026-11-02\n").unwrap();
        assert!(marker_says_sent(&marker, "2026-11-02"));
        assert!(!marker_says_sent(&marker, "2026-11-03"));
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn sent_message_id_is_recorded() {
        let dir = temp_dir("record");
        let path = dir.join("last-message.json");
        record_sent_message(
            &path,
            r#"{"ok": true, "result": {"message_id": 4242}}"#,
            "123",
            "2026-11-02",
        );
        let written = std::fs::read_to_string(&path).unwrap();
        assert!(written.contains("\"message_id\": 4242"), "{written}");
        assert!(written.contains("\"date\": \"2026-11-02\""), "{written}");
        // A body without a result is not fatal, and writes nothing.
        std::fs::remove_file(&path).unwrap();
        record_sent_message(&path, r#"{"ok": false}"#, "123", "2026-11-02");
        assert!(!path.exists());
        std::fs::remove_dir_all(&dir).ok();
    }
}
