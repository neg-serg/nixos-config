//! Natural-language actions for the shared trantor Telegram bot (`/do`).
//!
//! The bot already answers free text with the local model. `/do <text>` is a
//! different path: the model is asked for one strict JSON command, the command
//! is validated against a small allow-list, and only then is a fixed program
//! (currently the rutracker search) executed. The model never gets a shell:
//! arguments are passed as argv to `rt.py`, and an unknown action, a missing
//! argument or an out-of-range limit is rejected with a help reply.
//!
//! Captcha is handled by the execution layer, not here: `rt.py` drives the
//! live Vivaldi session that already carries `cf_clearance` for rutracker.
//! When that session is stale the script finds no rows; the reply then tells
//! the user to refresh rutracker in Vivaldi, because no local model can solve
//! Cloudflare.
//!
//! Environment (set by the pill-bot wrapper):
//!   PILL_BOT_ACTION_MODEL  planner model (default: PILL_BOT_LLM_MODEL)
//!   PILL_BOT_RT_PY         venv python for the rutracker skill
//!   PILL_BOT_RT_SCRIPT     rt.py path
//!   PILL_BOT_HOME          home that owns the skill (default /home/neg)

use std::io::Write;
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Instant;

use crate::shared::json::{self, Value};
use crate::{env_or, Api, DEFAULT_CURL};

const DEFAULT_LLM_MODEL: &str = "qwen3-vl-8b-abliterated";
const DEFAULT_HOME: &str = "/home/neg";
const DEFAULT_RT_PY: &str = ".dsh/skills/rutracker/scripts/.venv/bin/python";
const DEFAULT_RT_SCRIPT: &str = ".dsh/skills/rutracker/scripts/rt.py";
const DEFAULT_LIMIT: u32 = 20;
const MAX_LIMIT: u32 = 50;
const MAX_INPUT_CHARS: usize = 2000;
const MAX_QUERY_CHARS: usize = 200;
const PLACEHOLDER: &str = "⏳ Планирую запрос…";

const HELP: &str = "🤖 /do <запрос> — естественный язык в одно проверенное действие.\n\n\
Сейчас умею: поиск на рутрекере (сортировка по сидам).\n\
Пример: /do найди на рутрекере кольца власти 2160p, первые 30\n\n\
Модель локальная, действие валидируется до запуска.";

const SYSTEM: &str = "You are the command planner for the trantor Telegram bot. \
Return ONLY one JSON object, no markdown and no prose. Allowed shapes:\n\
{\"action\":\"rutracker_search\",\"args\":{\"query\":\"...\",\"limit\":20}}\n\
{\"action\":\"none\"}\n\
Rules:\n\
- rutracker_search: the user wants a title search on rutracker.org. \
args.query is the search phrase without site words like \"рутрекер\", \"найди\" or \
\"открой\"; args.limit is an integer 1..50 (default 20). Results are sorted by seeders.\n\
- none: any other request (questions, notes, status, unclear input).\n\
Examples:\n\
\"найди на рутрекере кольца власти 2160p, первые 30\" -> \
{\"action\":\"rutracker_search\",\"args\":{\"query\":\"кольца власти 2160p\",\"limit\":30}}\n\
\"как дела\" -> {\"action\":\"none\"}";

static BUSY: AtomicBool = AtomicBool::new(false);

enum Action {
    Rutracker { query: String, limit: u32 },
    None,
}

pub fn handle_message(api: &Api, chat_id: &str, text: &str, reply_to: Option<i64>, once: bool) {
    let text = text.trim();
    if text.is_empty() {
        crate::ask::deliver(api, chat_id, HELP, reply_to, None);
        return;
    }
    let text = truncate(text, MAX_INPUT_CHARS);
    if once {
        run(api, chat_id, &text, reply_to);
        return;
    }
    if BUSY.swap(true, Ordering::SeqCst) {
        crate::ask::deliver(
            api,
            chat_id,
            "⏳ Уже выполняю предыдущее действие — дождись ответа.",
            reply_to,
            None,
        );
        return;
    }
    let api = api.clone();
    let chat_id = chat_id.to_string();
    let _ = std::thread::Builder::new()
        .name("telegram-do".into())
        .spawn(move || {
            run(&api, &chat_id, &text, reply_to);
            BUSY.store(false, Ordering::SeqCst);
        });
}

fn run(api: &Api, chat_id: &str, text: &str, reply_to: Option<i64>) {
    let started = Instant::now();
    let placeholder = send_message(api, chat_id, PLACEHOLDER, reply_to);
    let answer = match plan(text) {
        Ok(Action::None) => "🤷 Это не действие из моего списка. Сейчас умею только поиск на \
рутрекере: /do найди …\n\nДобавить меня в группу может только человек: \
настройки чата → Add member → @trantortgbot, затем пришли в группе /chatid."
            .to_string(),
        Ok(action) => execute(action),
        Err(error) => format!("⚠️ Не смог составить команду: {error}\n\n{HELP}"),
    };
    eprintln!(
        "do: handled in {:.1}s ({} chars)",
        started.elapsed().as_secs_f64(),
        answer.chars().count()
    );
    crate::ask::deliver(api, chat_id, &answer, reply_to, placeholder);
}

/// Ask the model for one command and validate every field before it can run.
fn plan(text: &str) -> Result<Action, String> {
    let body = Value::Object(vec![
        (
            "model".to_string(),
            Value::Str(env_or(
                "PILL_BOT_ACTION_MODEL",
                &env_or("PILL_BOT_LLM_MODEL", DEFAULT_LLM_MODEL),
            )),
        ),
        (
            "messages".to_string(),
            Value::Array(vec![message("system", SYSTEM), message("user", text)]),
        ),
        ("max_tokens".to_string(), Value::Number(200.0)),
        ("temperature".to_string(), Value::Number(0.0)),
        (
            "response_format".to_string(),
            Value::Object(vec![(
                "type".to_string(),
                Value::Str("json_object".to_string()),
            )]),
        ),
        ("stream".to_string(), Value::Bool(false)),
    ])
    .dump(None);

    let base = env_or("PILL_BOT_LLM_URL", "http://127.0.0.1:9292");
    let url = format!("{}/v1/chat/completions", base.trim_end_matches('/'));
    let timeout = env_or("PILL_BOT_LLM_TIMEOUT", "180");
    let curl = env_or("PILL_BOT_CURL", DEFAULT_CURL);
    let mut child = Command::new(&curl)
        .args([
            "-sS",
            "--max-time",
            timeout.as_str(),
            "-H",
            "Content-Type: application/json",
            "--data-binary",
            "@-",
            url.as_str(),
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| format!("curl: {error}"))?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(body.as_bytes())
            .map_err(|error| format!("curl stdin: {error}"))?;
    }
    let output = child
        .wait_with_output()
        .map_err(|error| format!("curl: {error}"))?;
    if !output.status.success() {
        let error = String::from_utf8_lossy(&output.stderr).trim().to_string();
        return Err(if error.is_empty() {
            format!("curl exit {}", output.status.code().unwrap_or(-1))
        } else {
            error
        });
    }
    let raw = String::from_utf8_lossy(&output.stdout);
    let reply = json::parse(&raw)
        .and_then(|value| {
            value
                .get("choices")
                .and_then(Value::as_array)
                .and_then(|choices| choices.first())
                .and_then(|choice| choice.get("message"))
                .and_then(|message| message.get("content"))
                .and_then(Value::as_str)
                .map(str::to_string)
        })
        .ok_or_else(|| "модель вернула не-JSON".to_string())?;
    parse_command(&reply)
}

fn message(role: &str, content: &str) -> Value {
    Value::Object(vec![
        ("role".to_string(), Value::Str(role.to_string())),
        ("content".to_string(), Value::Str(content.to_string())),
    ])
}

fn parse_command(reply: &str) -> Result<Action, String> {
    let cleaned = strip_fences(reply);
    let value = json::parse(&cleaned).ok_or_else(|| "не JSON после модели".to_string())?;
    let action = value
        .get("action")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim();
    match action {
        "none" => Ok(Action::None),
        "rutracker_search" => {
            let args = value.get("args").ok_or_else(|| "нет args".to_string())?;
            let query = args
                .get("query")
                .and_then(Value::as_str)
                .map(str::trim)
                .unwrap_or("");
            validate_query(query)?;
            let limit = match args.get("limit") {
                None => DEFAULT_LIMIT,
                Some(Value::Number(number)) => {
                    let number = *number;
                    if number.fract() != 0.0 || number < 1.0 || number > MAX_LIMIT as f64 {
                        return Err(format!("limit вне 1..{MAX_LIMIT}"));
                    }
                    number as u32
                }
                Some(_) => return Err("limit не число".to_string()),
            };
            Ok(Action::Rutracker {
                query: query.to_string(),
                limit,
            })
        }
        other => Err(format!("неизвестное действие {other:?}")),
    }
}

fn validate_query(query: &str) -> Result<(), String> {
    if query.is_empty() {
        return Err("пустой query".to_string());
    }
    if query.chars().count() > MAX_QUERY_CHARS {
        return Err("query слишком длинный".to_string());
    }
    if query.chars().any(|ch| ch.is_control()) {
        return Err("в query есть управляющие символы".to_string());
    }
    Ok(())
}

fn execute(action: Action) -> String {
    match action {
        Action::None => "🤷 Действие не выбрано.".to_string(),
        Action::Rutracker { query, limit } => {
            let py = rutracker_path("PILL_BOT_RT_PY", DEFAULT_RT_PY);
            let script = rutracker_path("PILL_BOT_RT_SCRIPT", DEFAULT_RT_SCRIPT);
            if !Path::new(&py).is_file() || !Path::new(&script).is_file() {
                return format!("⚠️ Не нашёл rutracker-адаптер:\n{py}\n{script}");
            }
            let output = Command::new(&py)
                .arg(&script)
                .args(["search", &query, "--limit", &limit.to_string()])
                .env("HOME", env_or("PILL_BOT_HOME", DEFAULT_HOME))
                .env("RT_CDP_PORT", "9222")
                .output();
            let output = match output {
                Ok(output) => output,
                Err(error) => return format!("⚠️ Не смог запустить rutracker-адаптер: {error}"),
            };
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !output.status.success() {
                let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
                return format!(
                    "⚠️ Поиск упал ({}):\n{}",
                    output.status.code().unwrap_or(-1),
                    truncate(&stderr, 1500)
                );
            }
            if stdout.is_empty() {
                return "🔎 Рутрекер вернул пустую выдачу.".to_string();
            }
            let mut reply =
                format!("🔎 rutracker: «{query}» (лимит {limit}, сортировка по сидам)\n\n{stdout}");
            if stdout.contains("ничего не найдено") {
                reply.push_str(
                    "\n\nЕсли результаты ожидались — открой rutracker.org в Vivaldi, \
пройди проверку Cloudflare и повтори: сессия для капчи протухла.",
                );
            }
            reply
        }
    }
}

fn rutracker_path(name: &str, relative: &str) -> String {
    let home = env_or("PILL_BOT_HOME", DEFAULT_HOME);
    env_or(name, &format!("{home}/{relative}"))
}

fn strip_fences(reply: &str) -> String {
    let trimmed = reply.trim();
    let without = trimmed
        .strip_prefix("```json")
        .or_else(|| trimmed.strip_prefix("```"))
        .unwrap_or(trimmed);
    without
        .strip_suffix("```")
        .unwrap_or(without)
        .trim()
        .to_string()
}

fn send_message(api: &Api, chat_id: &str, text: &str, reply_to: Option<i64>) -> Option<i64> {
    let mut params = vec![("chat_id", chat_id.to_string()), ("text", text.to_string())];
    if let Some(message_id) = reply_to {
        params.push(("reply_to_message_id", message_id.to_string()));
    }
    let response = api.call("sendMessage", &params)?;
    let value = json::parse(&response)?;
    if !matches!(value.get("ok"), Some(Value::Bool(true))) {
        return None;
    }
    value
        .get("result")?
        .get("message_id")
        .and_then(Value::as_i64)
}

fn truncate(text: &str, limit: usize) -> String {
    let mut out = String::new();
    for ch in text.chars() {
        if out.len() + ch.len_utf8() > limit {
            break;
        }
        out.push(ch);
    }
    out.trim().to_string()
}
