//! `/screenshot [window]` — capture one Hyprland window and send it as a
//! Telegram document.
//!
//! The bot runs as root, so the compositor work is delegated to the desktop
//! user with `runuser`: `hyprctl -j` finds the window and its logical geometry,
//! and `grim -g` captures exactly that region (grim scales the crop by the
//! output scale, so a 2x desktop yields a 2x image). Single-monitor layout is
//! assumed, which is what trantor has.
//!
//! The screenshot is written into the bot's PrivateTmp as `neg`, uploaded with
//! `sendDocument` (Telegram preserves document pixels; photos are re-encoded)
//! and removed afterwards.
//!
//! Environment (set by the pill-bot wrapper):
//!   PILL_BOT_DESKTOP_USER     desktop user (default neg)
//!   PILL_BOT_XDG_RUNTIME_DIR  /run/user/<uid>
//!   PILL_BOT_WAYLAND_DISPLAY  wayland-1
//!   PILL_BOT_HYPRCTL, PILL_BOT_GRIM, PILL_BOT_RUNUSER  explicit binaries

use std::fs;
use std::process::Command;

use crate::shared::json::{self, Value};
use crate::{env_or, Api};

const DEFAULT_USER: &str = "neg";
const DEFAULT_RUNTIME: &str = "/run/user/1000";
const DEFAULT_DISPLAY: &str = "wayland-1";

pub fn handle(api: &Api, chat_id: &str, arg: &str, reply_to: Option<i64>) {
    let user = env_or("PILL_BOT_DESKTOP_USER", DEFAULT_USER);
    let runtime = env_or("PILL_BOT_XDG_RUNTIME_DIR", DEFAULT_RUNTIME);
    let display = env_or("PILL_BOT_WAYLAND_DISPLAY", DEFAULT_DISPLAY);
    let Some(signature) = hypr_signature(&runtime) else {
        reply(
            api,
            chat_id,
            "⚠️ Не нашёл Hyprland-сессию: нет каталога /run/user/.../hypr.",
            reply_to,
        );
        return;
    };

    let query = arg.trim().to_lowercase();
    eprintln!("screen: sig={signature} query={query:?}");
    let window = match find_window(&user, &runtime, &display, &signature, &query) {
        Ok(window) => window,
        Err(error) => {
            reply(api, chat_id, &format!("⚠️ {error}"), reply_to);
            return;
        }
    };
    let title = window
        .get("title")
        .and_then(Value::as_str)
        .unwrap_or("окно")
        .to_string();
    if matches!(window.get("hidden"), Some(Value::Bool(true)))
        || matches!(window.get("visible"), Some(Value::Bool(false)))
    {
        reply(
            api,
            chat_id,
            &format!(
                "⚠️ Окно «{title}» не на активном рабочем столе — переключись на него и повтори."
            ),
            reply_to,
        );
        return;
    }
    eprintln!("screen: window {title:?}");
    let Some((x, y, width, height)) = geometry(&window) else {
        reply(api, chat_id, "⚠️ У окна нет геометрии.", reply_to);
        return;
    };

    let grim = env_or("PILL_BOT_GRIM", "grim");
    let path = format!("/tmp/trantor-window-{}.png", std::process::id());
    let geometry = format!("{x},{y} {width}x{height}");
    eprintln!("screen: grim -g {geometry}");
    let output = run_as(
        &user,
        &runtime,
        &display,
        &signature,
        &grim,
        &["-g", geometry.as_str(), path.as_str()],
    );
    match output {
        Ok(output) if !output.status.success() => {
            let error = String::from_utf8_lossy(&output.stderr).trim().to_string();
            reply(
                api,
                chat_id,
                &format!("⚠️ grim не снял окно: {error}"),
                reply_to,
            );
            return;
        }
        Ok(_) => {}
        Err(error) => {
            reply(api, chat_id, &format!("⚠️ {error}"), reply_to);
            return;
        }
    }
    if fs::metadata(&path).map(|meta| meta.len()).unwrap_or(0) == 0 {
        reply(api, chat_id, "⚠️ grim создал пустой файл.", reply_to);
        let _ = fs::remove_file(&path);
        return;
    }

    eprintln!(
        "screen: captured {} bytes, sending",
        fs::metadata(&path).map(|meta| meta.len()).unwrap_or(0)
    );
    let caption = format!("📸 {title}");
    let caption = truncate(&caption, 900);
    let sent = api.send_document(chat_id, &path, &caption);
    let _ = fs::remove_file(&path);
    match sent {
        Some(response) => {
            let ok = json::parse(&response)
                .map(|value| matches!(value.get("ok"), Some(Value::Bool(true))))
                .unwrap_or(false);
            if !ok {
                let description = json::parse(&response)
                    .and_then(|value| {
                        value
                            .get("description")
                            .and_then(Value::as_str)
                            .map(str::to_string)
                    })
                    .unwrap_or_else(|| "sendDocument: ошибка Telegram".to_string());
                reply(api, chat_id, &format!("⚠️ {description}"), reply_to);
            }
        }
        None => reply(
            api,
            chat_id,
            "⚠️ Не смог отправить скриншот в Telegram.",
            reply_to,
        ),
    }
}

fn reply(api: &Api, chat_id: &str, text: &str, reply_to: Option<i64>) {
    eprintln!("screen: {text}");
    crate::ask::deliver(api, chat_id, text, reply_to, None);
}

fn hypr_signature(runtime: &str) -> Option<String> {
    let dir = format!("{runtime}/hypr");
    let mut entries = fs::read_dir(dir).ok()?;
    entries
        .next()?
        .ok()
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
}

fn find_window(
    user: &str,
    runtime: &str,
    display: &str,
    signature: &str,
    query: &str,
) -> Result<Value, String> {
    if query.is_empty() {
        let window = hypr_json(user, runtime, display, signature, "activewindow")?;
        if window.get("title").and_then(Value::as_str).is_none() {
            return Err("нет активного окна".to_string());
        }
        return Ok(window);
    }
    let clients = hypr_json(user, runtime, display, signature, "clients")?;
    let list = clients
        .as_array()
        .ok_or_else(|| "hyprctl clients вернул не список".to_string())?;
    for window in list {
        let title = window.get("title").and_then(Value::as_str).unwrap_or("");
        let class = window.get("class").and_then(Value::as_str).unwrap_or("");
        if title.to_lowercase().contains(query) || class.to_lowercase().contains(query) {
            return Ok(window.clone());
        }
    }
    let mut titles: Vec<&str> = list
        .iter()
        .filter_map(|window| window.get("title").and_then(Value::as_str))
        .take(6)
        .collect();
    titles.sort_unstable();
    Err(format!(
        "Окно «{query}» не найдено. Сейчас открыты: {}.",
        titles.join(", ")
    ))
}

fn geometry(window: &Value) -> Option<(i64, i64, i64, i64)> {
    let at = window.get("at")?.as_array()?;
    let size = window.get("size")?.as_array()?;
    let x = at.first()?.as_i64()?;
    let y = at.get(1)?.as_i64()?;
    let width = size.first()?.as_i64()?;
    let height = size.get(1)?.as_i64()?;
    Some((x, y, width, height))
}

fn hypr_json(
    user: &str,
    runtime: &str,
    display: &str,
    signature: &str,
    method: &str,
) -> Result<Value, String> {
    let hyprctl = env_or("PILL_BOT_HYPRCTL", "hyprctl");
    let output = run_as(user, runtime, display, signature, &hyprctl, &["-j", method])
        .map_err(|error| format!("hyprctl: {error}"))?;
    if !output.status.success() {
        let error = String::from_utf8_lossy(&output.stderr).trim().to_string();
        return Err(format!("hyprctl {method}: {error}"));
    }
    json::parse(&String::from_utf8_lossy(&output.stdout))
        .ok_or_else(|| format!("hyprctl {method}: не-JSON"))
}

fn run_as(
    user: &str,
    runtime: &str,
    display: &str,
    signature: &str,
    program: &str,
    args: &[&str],
) -> Result<std::process::Output, String> {
    let runuser = env_or("PILL_BOT_RUNUSER", "runuser");
    let mut command = Command::new(runuser);
    command
        .arg("-u")
        .arg(user)
        .arg("--")
        .arg("env")
        .arg(format!("XDG_RUNTIME_DIR={runtime}"))
        .arg(format!("WAYLAND_DISPLAY={display}"))
        .arg(format!("HYPRLAND_INSTANCE_SIGNATURE={signature}"))
        .arg(program)
        .args(args.iter().copied())
        .output()
        .map_err(|error| format!("{program}: {error}"))
}

fn truncate(text: &str, limit: usize) -> String {
    let mut out = String::new();
    for ch in text.chars() {
        if out.len() + ch.len_utf8() > limit {
            break;
        }
        out.push(ch);
    }
    out
}
