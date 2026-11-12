//! Herdr control for the shared trantor Telegram bot.
//!
//! Herdr is the terminal workspace manager the dsh farm runs in. This module
//! gives the bot its CLI: a deterministic `/herdr` command family for the
//! owner's private chat, plus the matching model tools (read-only ones always,
//! the writes only when the message asks for them, see `write_intent`).
//!
//! The bot's systemd unit runs as root while the Herdr server belongs to the
//! desktop user, so every call drops to that user with `runuser` — exactly like
//! the notes writes in `notes.rs`. `HERDR_SOCKET_PATH` points at the user's
//! socket; the API commands only read it, so the read-only home mount needs no
//! extra writable path.
//!
//! Commands:
//!   /herdr                      workspaces, tabs, panes and agent states
//!   /herdr read <pane> [lines]  tail of a pane's terminal output
//!   /herdr run <pane> <cmd...>  type a command into a shell pane
//!   /herdr prompt <pane> <text> submit a task to an agent and wait for state
//!
//! Environment (set by the unit, hosts/trantor/services/telegram-units.nix):
//!   PILL_BOT_HERDR           1/enabled (default) or 0/false to disable
//!   PILL_BOT_HERDR_BIN       herdr binary (default /run/current-system/sw/bin/herdr)
//!   PILL_BOT_HERDR_SOCKET    server socket (default <home>/.config/herdr/herdr.sock)
//!   PILL_BOT_HERDR_USER      desktop user owning the server (default PILL_BOT_OWNER)
//!   PILL_BOT_HERDR_TIMEOUT_MS  prompt wait budget in ms (default 120000)
//!   PILL_BOT_RUNUSER         privilege-dropping helper (default runuser)

use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};

use crate::shared::json::{self, Value};
use crate::{env_or, Api};

const DEFAULT_BIN: &str = "/run/current-system/sw/bin/herdr";
const DEFAULT_OWNER: &str = "neg";
const DEFAULT_READ_LINES: usize = 40;
const MAX_READ_LINES: usize = 200;
const MAX_TEXT_CHARS: usize = 2000;
/// One Telegram message holds ~4000 characters; keeping a read below that
/// means one reply per `/herdr read` even for a busy pane.
const MAX_READ_CHARS: usize = 3600;
/// A tool result is model context, not a terminal dump: the tail is enough and
/// the next tool round still fits into the model's window.
const MAX_TOOL_CHARS: usize = 2000;
const MAX_WORKSPACES: usize = 10;
const MAX_TABS: usize = 12;
const MAX_PANES_PER_TAB: usize = 8;
const DEFAULT_PROMPT_TIMEOUT_MS: &str = "120000";

const HELP: &str = "🐚 herdr — терминальная ферма агентов.\n\n\
/herdr — воркспейсы, вкладки, панели и состояние агентов.\n\
/herdr read <панель> [строк] — хвост вывода (по умолчанию 40, максимум 200).\n\
/herdr run <панель> <команда> — выполнить в shell-панели (текст + Enter).\n\
/herdr prompt <панель|агент> <текст> — отправить агенту и дождаться состояния.\n\n\
Панель — id вида w1:p2 (его показывает /herdr). Имя агента годится, если оно задано в Herdr.\n\
Выполняется от имени владельца Herdr; работает только в личном чате.";

/// One prompt wait at a time: it blocks up to the timeout and stacking two
/// would only answer the wrong message with the right state.
static PROMPTING: AtomicBool = AtomicBool::new(false);

#[derive(Debug, PartialEq)]
pub enum Action {
    Overview,
    Help,
    Read { target: String, lines: usize },
    Run { pane: String, command: String },
    Prompt { target: String, text: String },
}

pub fn enabled() -> bool {
    !matches!(
        std::env::var("PILL_BOT_HERDR"),
        Ok(value) if value == "0" || value.eq_ignore_ascii_case("false")
    )
}

/// Read-only tools are always offered to the model; the write tools need the
/// user to name a Herdr object (pane/agent/workspace/tab) *and* ask for an
/// action. Without both, a message like "запусти тесты" must not become a
/// command typed into somebody's terminal.
pub fn write_intent(question: &str) -> bool {
    const NOUNS: &[&str] = &[
        "herdr",
        "хердр",
        "панел",
        "пейн",
        "pane",
        "агент",
        "agent",
        "воркспейс",
        "workspace",
        "вкладк",
    ];
    const VERBS: &[&str] = &[
        "запусти",
        "запустить",
        "выполни",
        "выполнить",
        "отправь",
        "отправить",
        "спроси",
        "спросить",
        "поставь задачу",
        "поставить задачу",
        "передай",
        "передать",
        "напиши",
        "написать",
        "попроси",
        "попросить",
        "run",
        "prompt",
        "send",
        "launch",
        "ask",
    ];
    let question = question.to_lowercase();
    NOUNS.iter().any(|noun| question.contains(noun))
        && VERBS.iter().any(|verb| question.contains(verb))
}

pub fn handle_message(api: &Api, chat_id: &str, rest: &str, reply_to: Option<i64>, once: bool) {
    match parse(rest) {
        Action::Help => deliver(api, chat_id, HELP, reply_to),
        Action::Overview => deliver_result(api, chat_id, overview(), reply_to),
        Action::Read { target, lines } => {
            let result = read_target(&target, lines)
                .map(|text| format!("🐚 herdr read {target} ({lines} строк)\n{text}"));
            deliver_result(api, chat_id, result, reply_to);
        }
        Action::Run { pane, command } => {
            deliver_result(api, chat_id, run_in_pane(&pane, &command), reply_to);
        }
        Action::Prompt { target, text } => {
            prompt(api, chat_id, &target, &text, reply_to, once);
        }
    }
}

pub fn parse(rest: &str) -> Action {
    let rest = rest.trim();
    let mut parts = rest.splitn(2, char::is_whitespace);
    let sub = parts.next().unwrap_or("").to_lowercase();
    let tail = parts.next().unwrap_or("").trim();
    match sub.as_str() {
        "" | "status" | "list" | "ls" | "обзор" => Action::Overview,
        "help" | "?" | "помощь" => Action::Help,
        "read" | "cat" | "чтение" => {
            let (target, rest) = take_arg(tail);
            if target.is_empty() {
                return Action::Help;
            }
            // A non-numeric tail is the caller's typo, not a reason to fail:
            // the default is still a useful read.
            let lines = rest
                .trim()
                .parse::<usize>()
                .map(|lines| lines.clamp(1, MAX_READ_LINES))
                .unwrap_or(DEFAULT_READ_LINES);
            Action::Read { target, lines }
        }
        "run" | "exec" | "выполни" => {
            let (pane, command) = take_arg(tail);
            let command = command.trim();
            if pane.is_empty() || command.is_empty() {
                return Action::Help;
            }
            Action::Run {
                pane,
                command: truncate(command, MAX_TEXT_CHARS),
            }
        }
        "prompt" | "ask" | "спроси" => {
            let (target, text) = take_arg(tail);
            let text = text.trim();
            if target.is_empty() || text.is_empty() {
                return Action::Help;
            }
            Action::Prompt {
                target,
                text: truncate(text, MAX_TEXT_CHARS),
            }
        }
        _ => Action::Help,
    }
}

/// `take_arg` splits off the first whitespace-delimited token (a pane id or an
/// agent name) and returns it with the rest of the line.
fn take_arg(input: &str) -> (String, &str) {
    let input = input.trim();
    match input.find(char::is_whitespace) {
        Some(at) => (input[..at].to_string(), input[at..].trim()),
        None => (input.to_string(), ""),
    }
}

fn prompt(api: &Api, chat_id: &str, target: &str, text: &str, reply_to: Option<i64>, once: bool) {
    if once {
        let reply = prompt_agent(target, text);
        deliver(api, chat_id, &reply, reply_to);
        return;
    }
    if PROMPTING.swap(true, Ordering::SeqCst) {
        deliver(
            api,
            chat_id,
            "⏳ Уже жду ответа агента — дождись сообщения.",
            reply_to,
        );
        return;
    }
    let placeholder = crate::ask::send_message(
        api,
        chat_id,
        &format!("⏳ herdr: отправил агенту {target}, жду состояния…"),
        reply_to,
    );
    let thread_api = api.clone();
    let thread_chat = chat_id.to_string();
    let thread_target = target.to_string();
    let thread_text = text.to_string();
    let spawned = std::thread::Builder::new()
        .name("telegram-herdr-prompt".into())
        .spawn(move || {
            let reply = prompt_agent(&thread_target, &thread_text);
            PROMPTING.store(false, Ordering::SeqCst);
            crate::ask::deliver(&thread_api, &thread_chat, &reply, reply_to, placeholder);
        });
    if spawned.is_err() {
        PROMPTING.store(false, Ordering::SeqCst);
        eprintln!("herdr: cannot spawn the prompt thread");
        deliver(
            api,
            chat_id,
            "⚠️ Не удалось запустить ожидание ответа агента.",
            reply_to,
        );
    }
}

fn deliver(api: &Api, chat_id: &str, text: &str, reply_to: Option<i64>) {
    crate::ask::deliver(api, chat_id, text, reply_to, None);
}

fn deliver_result(api: &Api, chat_id: &str, result: Result<String, String>, reply_to: Option<i64>) {
    let text = match result {
        Ok(text) => text,
        Err(error) => format!("⚠️ herdr: {error}"),
    };
    deliver(api, chat_id, &text, reply_to);
}

// -- the herdr CLI -----------------------------------------------------

fn herdr_user() -> String {
    env_or(
        "PILL_BOT_HERDR_USER",
        &env_or("PILL_BOT_OWNER", DEFAULT_OWNER),
    )
}

fn herdr_home() -> String {
    env_or("PILL_BOT_HOME", &format!("/home/{}", herdr_user()))
}

fn socket_path() -> String {
    env_or(
        "PILL_BOT_HERDR_SOCKET",
        &format!("{}/.config/herdr/herdr.sock", herdr_home()),
    )
}

/// One herdr invocation, dropped to the desktop user when the unit runs as
/// root. `HERDR_SOCKET_PATH` is what makes the binary talk to that user's
/// server; `HOME` keeps the client from looking in root's config directory.
fn execute(args: &[&str]) -> Result<String, String> {
    let bin = env_or("PILL_BOT_HERDR_BIN", DEFAULT_BIN);
    let user = herdr_user();
    let drop = is_root() && !user.is_empty() && user != "root";
    let mut command = if drop {
        let mut command = Command::new(env_or("PILL_BOT_RUNUSER", "runuser"));
        command.arg("-u").arg(&user).arg("--").arg(&bin);
        command
    } else {
        Command::new(&bin)
    };
    command.args(args);
    command.env("HERDR_SOCKET_PATH", socket_path());
    if drop {
        command.env("HOME", herdr_home());
        command.env("USER", &user);
        command.env("LOGNAME", &user);
        command.current_dir("/tmp");
    }
    let output = command
        .output()
        .map_err(|error| format!("{bin}: {error}"))?;
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    if let Some(error) = error_of(&stdout).or_else(|| error_of(&stderr)) {
        return Err(friendly(&error));
    }
    if !output.status.success() {
        let detail = stderr.trim();
        let error = if detail.is_empty() {
            format!("herdr exit {}", output.status.code().unwrap_or(-1))
        } else {
            truncate(detail, 600)
        };
        return Err(friendly(&error));
    }
    Ok(stdout)
}

/// Some CLI failures exit 0 and put `{"error": {...}}` on stdout; others use
/// stderr with a non-zero status. Both shapes are checked before the status.
fn error_of(text: &str) -> Option<String> {
    let trimmed = text.trim();
    if !trimmed.starts_with('{') {
        return None;
    }
    let value = json::parse(trimmed)?;
    let error = value.get("error")?;
    let code = error.get("code").and_then(Value::as_str).unwrap_or("herdr");
    let message = error.get("message").and_then(Value::as_str).unwrap_or("");
    Some(if message.is_empty() {
        code.to_string()
    } else {
        format!("{code}: {message}")
    })
}

/// Translate the codes a user can act on; everything else keeps the CLI text.
fn friendly(error: &str) -> String {
    let code = error.split(':').next().unwrap_or("").trim();
    let hint = match code {
        "agent_blocked" => " — агент ждёт ответа в Herdr: открой его и ответь в панели",
        "agent_prompt_stalled" => " — агент не принял ввод; проверь панель в Herdr",
        "timeout" => " — не дождался состояния агента",
        "pane_not_found" | "agent_not_found" => {
            " — такой панели или агента нет; /herdr покажет живые"
        }
        "server_not_running" | "connect_failed" => " — сервер Herdr не запущен",
        _ => "",
    };
    format!("{error}{hint}")
}

fn call(args: &[&str]) -> Result<Value, String> {
    let stdout = execute(args)?;
    json::parse(stdout.trim())
        .ok_or_else(|| format!("неожиданный ответ: {}", truncate(stdout.trim(), 200)))
}

fn prompt_timeout() -> String {
    env_or("PILL_BOT_HERDR_TIMEOUT_MS", DEFAULT_PROMPT_TIMEOUT_MS)
        .trim()
        .parse::<u64>()
        .ok()
        .filter(|ms| *ms >= 1_000 && *ms <= 600_000)
        .map(|ms| ms.to_string())
        .unwrap_or_else(|| DEFAULT_PROMPT_TIMEOUT_MS.to_string())
}

// -- operations ---------------------------------------------------------

fn overview() -> Result<String, String> {
    let response = call(&["workspace", "list"])?;
    let workspaces = response
        .get("result")
        .and_then(|result| result.get("workspaces"))
        .and_then(Value::as_array)
        .unwrap_or(&[]);
    if workspaces.is_empty() {
        return Ok("🐚 herdr: открытых воркспейсов нет.".to_string());
    }
    let mut views = Vec::new();
    for workspace in workspaces.iter().take(MAX_WORKSPACES) {
        let Some(id) = workspace.get("workspace_id").and_then(Value::as_str) else {
            continue;
        };
        // A workspace that disappears between calls must not lose the whole
        // overview: the missing detail is rendered as "нет данных".
        let tabs = call(&["tab", "list", "--workspace", id]).unwrap_or(Value::Null);
        let panes = call(&["pane", "list", "--workspace", id]).unwrap_or(Value::Null);
        views.push(WorkspaceView {
            workspace: workspace.clone(),
            tabs,
            panes,
        });
    }
    Ok(render_overview(&views, workspaces.len()))
}

struct WorkspaceView {
    workspace: Value,
    tabs: Value,
    panes: Value,
}

fn render_overview(views: &[WorkspaceView], total: usize) -> String {
    let mut out = String::from("🐚 herdr\n");
    for view in views {
        let workspace = &view.workspace;
        let id = field(workspace, "workspace_id");
        let label = field(workspace, "label");
        let status = field(workspace, "agent_status");
        let focus = if matches!(workspace.get("focused"), Some(Value::Bool(true))) {
            " · фокус"
        } else {
            ""
        };
        out.push_str(&format!("\n▪ {id}{}{} · {status}\n", quoted(&label), focus));
        let tabs = array_of(result_of(&view.tabs), "tabs");
        let panes = array_of(result_of(&view.panes), "panes");
        if tabs.is_empty() && panes.is_empty() {
            out.push_str("   (нет данных о вкладках и панелях)\n");
            continue;
        }
        for tab in tabs.iter().take(MAX_TABS) {
            let tab_id = field(tab, "tab_id");
            out.push_str(&format!(
                "   ▸ {tab_id}{} · {}\n",
                quoted(&field(tab, "label")),
                mark(&field(tab, "agent_status"))
            ));
            let mut shown = 0usize;
            for pane in panes {
                if field(pane, "tab_id") != tab_id {
                    continue;
                }
                if shown == MAX_PANES_PER_TAB {
                    out.push_str("       … ещё панели\n");
                    break;
                }
                shown += 1;
                let pane_id = field(pane, "pane_id");
                let agent = field_or(pane, "agent", "shell");
                let cwd = {
                    let foreground = field(pane, "foreground_cwd");
                    if foreground.is_empty() {
                        field(pane, "cwd")
                    } else {
                        foreground
                    }
                };
                let title = one_line(&field(pane, "terminal_title_stripped"), 70);
                let state = field(pane, "agent_status");
                out.push_str(&format!(
                    "       {pane_id}  {agent}{}{}{}\n",
                    if state.is_empty() {
                        String::new()
                    } else {
                        format!(" {}", mark(&state))
                    },
                    if cwd.is_empty() {
                        String::new()
                    } else {
                        format!("  {cwd}")
                    },
                    if title.is_empty() {
                        String::new()
                    } else {
                        format!("  {title}")
                    }
                ));
            }
        }
        if tabs.len() > MAX_TABS {
            out.push_str(&format!("   … ещё {} вкладок\n", tabs.len() - MAX_TABS));
        }
    }
    if total > views.len() {
        out.push_str(&format!(
            "\n… ещё {} воркспейсов (показаны первые {})\n",
            total - views.len(),
            views.len()
        ));
    }
    out
}

fn read_target(target: &str, lines: usize) -> Result<String, String> {
    match read_from("pane", target, lines) {
        Ok(text) => Ok(text),
        Err(pane_error) => match read_from("agent", target, lines) {
            Ok(text) => Ok(text),
            Err(agent_error) => {
                if looks_like_pane(target) {
                    Err(pane_error)
                } else {
                    Err(agent_error)
                }
            }
        },
    }
}

fn read_from(kind: &str, target: &str, lines: usize) -> Result<String, String> {
    let lines = lines.clamp(1, MAX_READ_LINES).to_string();
    let raw = execute(&[
        kind,
        "read",
        target,
        "--source",
        "recent-unwrapped",
        "--lines",
        &lines,
    ])?;
    let text = tidy(&strip_terminal(&raw));
    if text.is_empty() {
        return Err("панель пуста".to_string());
    }
    let (text, cut) = tail_bytes(&text, MAX_READ_CHARS);
    Ok(if cut {
        format!("… (начало обрезано)\n{text}")
    } else {
        text
    })
}

fn run_in_pane(pane: &str, command: &str) -> Result<String, String> {
    // `pane run` is admitted-or-error and prints nothing on success: parse
    // only the error shape, never require a JSON body here.
    execute(&["pane", "run", pane, command])?;
    Ok(format!("🐚 herdr: отправлено в {pane}\n$ {command}"))
}

/// Submit the task, wait for the first settled state and return the agent's
/// tail. A failed wait still returns the tail: the approval dialog or the
/// error is what the owner needs to see.
fn prompt_agent(target: &str, text: &str) -> String {
    let timeout = prompt_timeout();
    let result = execute(&[
        "agent",
        "prompt",
        target,
        text,
        "--wait",
        "--timeout",
        &timeout,
    ]);
    let mut reply = match &result {
        Ok(stdout) => {
            // The wait reports the settled state; an empty body still means
            // the prompt was admitted, so it must not read as a failure.
            let state = json::parse(stdout.trim())
                .and_then(|value| {
                    value
                        .get("result")
                        .and_then(|result| result.get("agent"))
                        .and_then(|agent| agent.get("agent_status"))
                        .and_then(Value::as_str)
                        .map(str::to_string)
                })
                .unwrap_or_else(|| "принято".to_string());
            format!("🐚 herdr: {target} → {}", mark(&state))
        }
        Err(error) => format!("⚠️ herdr: {error}"),
    };
    if let Ok(tail) = read_target(target, DEFAULT_READ_LINES) {
        if !tail.trim().is_empty() {
            reply.push_str("\n\n");
            reply.push_str(&tail);
        }
    }
    reply
}

// -- model tools --------------------------------------------------------

pub fn tools_json(write_allowed: bool) -> Value {
    let mut tools = vec![
        tool(
            "herdr_overview",
            "Показать воркспейсы, вкладки, панели и состояние агентов Herdr.",
            &[],
            &[],
        ),
        tool(
            "herdr_read",
            "Прочитать хвост вывода панели или агента Herdr.",
            &[
                (
                    "target",
                    "string",
                    "Id панели (w1:p2) или имя агента в Herdr.",
                ),
                (
                    "lines",
                    "integer",
                    "Сколько строк вернуть, 1..200 (по умолчанию 40).",
                ),
            ],
            &["target"],
        ),
    ];
    if write_allowed {
        tools.push(tool(
            "herdr_run",
            "Выполнить команду в shell-панели Herdr (текст + Enter). Только по прямой просьбе пользователя.",
            &[
                ("pane", "string", "Id панели, например w1:p2."),
                ("command", "string", "Команда, которая будет введена в панель."),
            ],
            &["pane", "command"],
        ));
        tools.push(tool(
            "herdr_prompt",
            "Отправить задачу агенту Herdr и дождаться его состояния. Только по прямой просьбе пользователя.",
            &[
                (
                    "target",
                    "string",
                    "Id панели (w1:p2) или имя агента в Herdr.",
                ),
                ("text", "string", "Текст задачи для агента."),
            ],
            &["target", "text"],
        ));
    }
    Value::Array(tools)
}

pub fn call_tool(name: &str, arguments: &str, write_allowed: bool) -> String {
    let arguments = json::parse(arguments.trim()).unwrap_or(Value::Null);
    let text_arg = |key: &str| {
        arguments
            .get(key)
            .and_then(Value::as_str)
            .unwrap_or("")
            .trim()
            .to_string()
    };
    let lines_arg = |fallback: usize| {
        arguments
            .get("lines")
            .and_then(Value::as_i64)
            .map(|lines| lines.clamp(1, MAX_READ_LINES as i64) as usize)
            .unwrap_or(fallback)
    };
    let result = match name {
        "herdr_overview" => overview(),
        "herdr_read" => {
            let target = text_arg("target");
            if target.is_empty() {
                Err("нужен target".to_string())
            } else {
                read_target(&target, lines_arg(DEFAULT_READ_LINES))
            }
        }
        "herdr_run" if write_allowed => {
            let pane = text_arg("pane");
            let command = text_arg("command");
            if pane.is_empty() || command.is_empty() {
                Err("нужны pane и command".to_string())
            } else {
                run_in_pane(&pane, &truncate(&command, MAX_TEXT_CHARS))
            }
        }
        "herdr_prompt" if write_allowed => {
            let target = text_arg("target");
            let text = text_arg("text");
            if target.is_empty() || text.is_empty() {
                Err("нужны target и text".to_string())
            } else {
                Ok(prompt_agent(&target, &truncate(&text, MAX_TEXT_CHARS)))
            }
        }
        _ => Err("инструмент недоступен".to_string()),
    };
    let text = match result {
        Ok(text) => text,
        Err(error) => format!("herdr: {error}"),
    };
    let (text, cut) = tail_bytes(&text, MAX_TOOL_CHARS);
    if cut {
        format!("… (обрезано)\n{text}")
    } else {
        text
    }
}

fn tool(
    name: &str,
    description: &str,
    properties: &[(&str, &str, &str)],
    required: &[&str],
) -> Value {
    let properties = properties
        .iter()
        .map(|(name, kind, description)| {
            (
                name.to_string(),
                Value::Object(vec![
                    ("type".to_string(), Value::Str(kind.to_string())),
                    (
                        "description".to_string(),
                        Value::Str(description.to_string()),
                    ),
                ]),
            )
        })
        .collect();
    Value::Object(vec![
        ("type".to_string(), Value::Str("function".to_string())),
        (
            "function".to_string(),
            Value::Object(vec![
                ("name".to_string(), Value::Str(name.to_string())),
                (
                    "description".to_string(),
                    Value::Str(description.to_string()),
                ),
                (
                    "parameters".to_string(),
                    Value::Object(vec![
                        ("type".to_string(), Value::Str("object".to_string())),
                        ("properties".to_string(), Value::Object(properties)),
                        (
                            "required".to_string(),
                            Value::Array(
                                required
                                    .iter()
                                    .map(|name| Value::Str(name.to_string()))
                                    .collect(),
                            ),
                        ),
                    ]),
                ),
            ]),
        ),
    ])
}

// -- text helpers -------------------------------------------------------

fn array_of<'a>(value: &'a Value, key: &str) -> &'a [Value] {
    value.get(key).and_then(Value::as_array).unwrap_or(&[])
}

/// Every herdr control response wraps its payload in `result`; the renderer
/// wants the payload, the error/log fields stay outside it.
fn result_of<'a>(response: &'a Value) -> &'a Value {
    response.get("result").unwrap_or(response)
}

fn field(value: &Value, key: &str) -> String {
    value
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string()
}

fn field_or(value: &Value, key: &str, fallback: &str) -> String {
    let text = field(value, key);
    if text.is_empty() {
        fallback.to_string()
    } else {
        text
    }
}

fn quoted(text: &str) -> String {
    if text.is_empty() {
        String::new()
    } else {
        format!(" «{text}»")
    }
}

fn mark(status: &str) -> String {
    let icon = match status {
        "working" => "⏳",
        "idle" => "✅",
        "blocked" => "🚧",
        "done" => "✔️",
        _ => "❔",
    };
    if status.is_empty() {
        icon.to_string()
    } else {
        format!("{icon} {status}")
    }
}

fn one_line(text: &str, limit: usize) -> String {
    let flat = text.split_whitespace().collect::<Vec<_>>().join(" ");
    truncate(&flat, limit)
}

fn looks_like_pane(target: &str) -> bool {
    target.starts_with('w') && target.contains(":p")
}

fn is_root() -> bool {
    std::fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|text| {
            text.lines()
                .find(|line| line.starts_with("Uid:"))
                .and_then(|line| line.split_whitespace().nth(1))
                .and_then(|value| value.parse::<u32>().ok())
        })
        .map(|uid| uid == 0)
        .unwrap_or(false)
}

/// Terminal snapshots carry a BOM, ANSI escapes and CRLF redraws; none of that
/// belongs in a Telegram message. Printable text, tabs and newlines stay.
fn strip_terminal(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut chars = text.chars().peekable();
    while let Some(ch) = chars.next() {
        match ch {
            '\u{feff}' | '\r' => {}
            '\u{1b}' => skip_escape(&mut chars),
            '\n' | '\t' => out.push(ch),
            ch if ch.is_control() => {}
            ch => out.push(ch),
        }
    }
    out
}

fn skip_escape(chars: &mut std::iter::Peekable<std::str::Chars<'_>>) {
    match chars.next() {
        Some('[') => {
            // CSI: parameters until one final byte in @..~
            while let Some(ch) = chars.peek().copied() {
                chars.next();
                if ('@'..='~').contains(&ch) {
                    break;
                }
            }
        }
        Some(']') => {
            // OSC: terminated by BEL or ST (ESC \)
            while let Some(ch) = chars.next() {
                if ch == '\u{7}' {
                    break;
                }
                if ch == '\u{1b}' {
                    if chars.peek() == Some(&'\\') {
                        chars.next();
                    }
                    break;
                }
            }
        }
        Some('(') | Some(')') => {
            chars.next();
        }
        _ => {}
    }
}

fn tidy(text: &str) -> String {
    let mut lines: Vec<&str> = text.lines().map(str::trim_end).collect();
    while lines.first().map_or(false, |line| line.trim().is_empty()) {
        lines.remove(0);
    }
    while lines.last().map_or(false, |line| line.trim().is_empty()) {
        lines.pop();
    }
    lines.join("\n")
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

/// Byte-bounded tail: the Telegram splitter and the model context are both
/// byte budgets, so the cut must never split a UTF-8 code point.
fn tail_bytes(text: &str, limit: usize) -> (String, bool) {
    if text.len() <= limit {
        return (text.to_string(), false);
    }
    let mut start = text.len() - limit;
    while !text.is_char_boundary(start) {
        start += 1;
    }
    (text[start..].to_string(), true)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[ignore = "needs a running Herdr server and its owner's socket"]
    fn live_overview_smoke() {
        let text = overview().expect("herdr overview");
        println!("{text}");
        assert!(text.starts_with("🐚 herdr"));
    }

    #[test]
    fn parse_routes_commands() {
        assert!(matches!(parse(""), Action::Overview));
        assert!(matches!(parse("status"), Action::Overview));
        assert!(matches!(parse("help"), Action::Help));
        match parse("read w1:p2 25") {
            Action::Read { target, lines } => {
                assert_eq!(target, "w1:p2");
                assert_eq!(lines, 25);
            }
            other => panic!("expected read, got {other:?}"),
        }
        match parse("read w1:p2") {
            Action::Read { target, lines } => {
                assert_eq!(target, "w1:p2");
                assert_eq!(lines, DEFAULT_READ_LINES);
            }
            other => panic!("expected read, got {other:?}"),
        }
        match parse("read w1:p2 9999") {
            Action::Read { lines, .. } => assert_eq!(lines, MAX_READ_LINES),
            other => panic!("expected read, got {other:?}"),
        }
        match parse("run w1:p2 cargo test --all") {
            Action::Run { pane, command } => {
                assert_eq!(pane, "w1:p2");
                assert_eq!(command, "cargo test --all");
            }
            other => panic!("expected run, got {other:?}"),
        }
        match parse("prompt w1:p2 прогони тесты") {
            Action::Prompt { target, text } => {
                assert_eq!(target, "w1:p2");
                assert_eq!(text, "прогони тесты");
            }
            other => panic!("expected prompt, got {other:?}"),
        }
        assert!(matches!(parse("read"), Action::Help));
        assert!(matches!(parse("run w1:p2"), Action::Help));
        assert!(matches!(parse("prompt w1:p2"), Action::Help));
        assert!(matches!(parse("bogus"), Action::Help));
    }

    #[test]
    fn write_intent_needs_a_herdr_object_and_an_action() {
        assert!(write_intent("поставь задачу агенту w1:p2: прогони тесты"));
        assert!(write_intent("запусти в панели w1:p2 cargo test"));
        assert!(!write_intent("запусти тесты"));
        assert!(!write_intent("что там в панели w1:p2?"));
        assert!(!write_intent("herdr"));
    }

    #[test]
    fn overview_renders_workspaces_tabs_panes() {
        let workspace = json::parse(
            r#"{"workspace_id":"w1","label":"nixos","agent_status":"working","focused":true}"#,
        )
        .expect("workspace fixture");
        let tabs = json::parse(
            r#"{"result":{"tabs":[{"tab_id":"w1:t1","label":"1","agent_status":"idle"}]}}"#,
        )
        .expect("tabs fixture");
        let panes = json::parse(
            r#"{"result":{"panes":[{"pane_id":"w1:p1","tab_id":"w1:t1","agent":"dsh","agent_status":"working","cwd":"/etc/nixos","terminal_title_stripped":"🐋 nixos"}]}}"#,
        )
        .expect("panes fixture");
        let view = WorkspaceView {
            workspace,
            tabs,
            panes,
        };
        let text = render_overview(&[view], 1);
        assert!(text.contains("▪ w1 «nixos»"), "{text}");
        assert!(text.contains("▸ w1:t1 «1»"), "{text}");
        assert!(
            text.contains("w1:p1  dsh ⏳ working  /etc/nixos  🐋 nixos"),
            "{text}"
        );
        assert!(!text.contains("ещё"), "{text}");
    }

    #[test]
    fn terminal_output_is_cleaned_and_capped() {
        let raw = "\u{feff}\u{1b}[32mok\u{1b}[0m\r\nerror   \n\n";
        assert_eq!(tidy(&strip_terminal(raw)), "ok\nerror");
        let long = "x".repeat(100);
        let (tail, cut) = tail_bytes(&long, 10);
        assert!(cut);
        assert_eq!(tail, "x".repeat(10));
        let (whole, cut) = tail_bytes("short", 10);
        assert!(!cut);
        assert_eq!(whole, "short");
    }

    #[test]
    fn cli_errors_are_recognised_before_exit_status() {
        let error = error_of(
            r#"{"error":{"code":"pane_not_found","message":"pane w9:p9 not found"},"id":"cli"}"#,
        )
        .expect("error");
        assert_eq!(error, "pane_not_found: pane w9:p9 not found");
        assert!(error_of("plain terminal text").is_none());
        assert!(error_of(r#"{"result":{"type":"workspace_list"}}"#).is_none());
    }

    #[test]
    fn tools_are_gated_by_write_intent() {
        let read_only = tools_json(false);
        let with_writes = tools_json(true);
        let names = |value: &Value| -> Vec<String> {
            value
                .as_array()
                .unwrap_or(&[])
                .iter()
                .filter_map(|tool| tool.get("function"))
                .filter_map(|function| function.get("name"))
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect()
        };
        assert_eq!(
            names(&read_only),
            vec!["herdr_overview".to_string(), "herdr_read".to_string()]
        );
        assert!(names(&with_writes).contains(&"herdr_run".to_string()));
        assert!(names(&with_writes).contains(&"herdr_prompt".to_string()));
    }
}
