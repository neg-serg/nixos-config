//! Notes for the monitoring bot.
//!
//! The chat is the phone-side interface to the `~/notes` zk notebook: create,
//! show, append, search, list, tag lookup, delete and the `nb` sync script
//! (pull, `zk index`, commit, push). The commands are deterministic and work
//! without the model; the same operations are also exposed to the local model
//! as OpenAI tool calls (see `ask.rs`), so free text like "запиши в заметки …"
//! and explicit commands share one implementation.
//!
//! The bot runs as root because it reads the root-owned bot secrets, so every
//! operation that touches the notebook drops to `PILL_BOT_OWNER` through
//! `runuser`: new files must stay neg-owned and `zk`/`git` need that user's
//! `HOME` (git config, SSH key and the proxy-wrapped `ssh` used for pushes).
//! The unit keeps `ProtectHome=read-only` and grants write access to the
//! notebook alone.
//!
//! Path safety: note paths are relative to the notebook, canonicalized and
//! checked against its root, so `..`, absolute paths and symlinks out of the
//! tree are rejected.
//!
//! Environment:
//!   PILL_BOT_NOTES_DIR     notebook root (default /home/neg/notes)
//!   PILL_BOT_OWNER         user owning the notebook (set by the unit)
//!   PILL_BOT_HOME          that user's home (default /home/$PILL_BOT_OWNER)
//!   PILL_BOT_NB            the `nb` sync script (default ~/.local/bin/nb)
//!   PILL_BOT_ZK            zk binary (default `zk` from PATH)
//!   PILL_BOT_RG            ripgrep binary (default `rg` from PATH)
//!   PILL_BOT_RUNUSER       privilege drop helper (default `runuser`)
//!   PILL_BOT_NB_TIMEOUT    seconds before `nb` is killed (default 90)
//!   PILL_BOT_NOTES_TOOLS=0 disable the model tools

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::shared::json::{self, Value};
use crate::{env_or, stamp_now, Api};

const DEFAULT_NOTEBOOK: &str = "/home/neg/notes";
const DEFAULT_RECENT: usize = 10;
const MAX_RECENT: usize = 25;
const MAX_TITLE_CHARS: usize = 120;
const MAX_QUERY_CHARS: usize = 200;
const MAX_SEARCH_HITS: usize = 8;
/// Telegram splits long answers anyway, but a whole book would become a dozen
/// messages; the cap keeps one note readable on a phone.
const MAX_SHOW_CHARS: usize = 12_000;
/// Tool output goes back into a 4B model's context.
const MAX_TOOL_RESULT: usize = 6_000;
const MAX_SYNC_REPORT: usize = 3_000;

const HELP: &str = "📝 Заметки (~/notes):\n\n\
/note <текст> — новая заметка, заголовок из первой строки.\n\
/note new <заголовок> — пустая заметка по шаблону zk.\n\
/note show <путь> — показать заметку.\n\
/note append <путь> <текст> — дописать с датой.\n\
/note rm <путь> --yes — удалить (в git остаётся история).\n\
/notes <запрос> — поиск по тексту и именам; /notes — последние.\n\
/notes recent [N] — последние N заметок.\n\
/notes tag <тег> — заметки с тегом.\n\
/nb — синхронизация: pull, zk index, commit, push.";

/// One parsed notes command. Owned strings keep the routing free of lifetimes:
/// the model-tool path builds actions from JSON, not from the message text.
#[derive(Debug, Clone, PartialEq)]
pub enum Action {
    Help,
    New { title: String, body: String },
    Show(String),
    Append { path: String, text: String },
    Remove { path: String, confirmed: bool },
    Search(String),
    Recent(usize),
    Tag(String),
    Sync,
}

/// Handle a text message when it is a notes command. Returns false so the
/// caller can fall through to `/status`, `/help` and the model Q&A.
pub fn handle_message(api: &Api, chat_id: &str, text: &str, reply_to: Option<i64>) -> bool {
    let Some(action) = parse(text) else {
        return false;
    };
    match action {
        Action::Sync => {
            // A push can wait on the network for a minute; the poll loop must
            // keep answering callback presses while it runs.
            let api = api.clone();
            let chat_id = chat_id.to_string();
            let spawned = std::thread::Builder::new()
                .name("telegram-notes-sync".into())
                .spawn(move || {
                    let reply = sync();
                    crate::ask::deliver(&api, &chat_id, &reply, None, None);
                });
            if spawned.is_err() {
                eprintln!("notes: cannot spawn the sync thread");
            }
        }
        action => {
            let reply = execute(&action);
            crate::ask::deliver(api, chat_id, &reply, reply_to, None);
        }
    }
    true
}

// -- parsing -----------------------------------------------------------

/// Route a text into a notes action. `None` means "not a notes command".
pub fn parse(text: &str) -> Option<Action> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return None;
    }
    let mut parts = trimmed.splitn(2, char::is_whitespace);
    let command = parts.next().unwrap_or("");
    let rest = parts.next().unwrap_or("").trim();
    let base = command.split('@').next().unwrap_or("").to_lowercase();
    match base.as_str() {
        "/note" | "/заметка" | "/записать" => Some(parse_note(rest)),
        "/notes" | "/заметки" | "/поиск" => Some(parse_notes(rest)),
        "/nb" | "/sync" | "/синк" => Some(Action::Sync),
        _ => None,
    }
}

fn parse_note(rest: &str) -> Action {
    if rest.is_empty() {
        return Action::Help;
    }
    let (head, tail) = take_arg(rest);
    match head.to_lowercase().as_str() {
        "help" | "помощь" => Action::Help,
        "new" | "новая" => {
            let (title, body) = split_title_body(tail);
            if title.is_empty() {
                Action::Help
            } else {
                Action::New { title, body }
            }
        }
        "show" | "open" | "показать" => {
            let (path, _) = take_arg(tail);
            if path.is_empty() {
                Action::Help
            } else {
                Action::Show(path)
            }
        }
        "append" | "add" | "дописать" => {
            let (path, text) = take_arg(tail);
            if path.is_empty() || text.trim().is_empty() {
                Action::Help
            } else {
                Action::Append {
                    path,
                    text: text.trim().to_string(),
                }
            }
        }
        "rm" | "delete" | "del" | "удалить" => {
            let (path, extra) = take_arg(tail);
            if path.is_empty() {
                Action::Help
            } else {
                Action::Remove {
                    path,
                    confirmed: extra
                        .split_whitespace()
                        .any(|word| matches!(word, "--yes" | "-y" | "да")),
                }
            }
        }
        // Anything else after `/note` is a quick capture: first line becomes
        // the title, the rest the body appended under the template heading.
        _ => {
            let (title, body) = split_title_body(rest);
            Action::New { title, body }
        }
    }
}

fn parse_notes(rest: &str) -> Action {
    if rest.is_empty() {
        return Action::Recent(DEFAULT_RECENT);
    }
    let (head, tail) = take_arg(rest);
    match head.to_lowercase().as_str() {
        "help" | "помощь" => Action::Help,
        "recent" | "last" | "последние" => Action::Recent(
            tail.split_whitespace()
                .next()
                .and_then(|value| value.parse().ok())
                .unwrap_or(DEFAULT_RECENT),
        ),
        "tag" | "тег" => {
            let tag = tail.trim().trim_start_matches('#').to_string();
            if tag.is_empty() {
                Action::Help
            } else {
                Action::Tag(tag)
            }
        }
        // `#tag` is a tag lookup, everything else a full-text search.
        _ if rest.starts_with('#') => Action::Tag(rest.trim_start_matches('#').to_string()),
        _ => Action::Search(rest.to_string()),
    }
}

/// Split one (possibly quoted) argument off the front of `input`.
fn take_arg(input: &str) -> (String, &str) {
    let input = input.trim_start();
    if let Some(rest) = input.strip_prefix('"') {
        if let Some(end) = rest.find('"') {
            return (rest[..end].to_string(), rest[end + 1..].trim_start());
        }
    }
    match input.find(char::is_whitespace) {
        Some(index) => (input[..index].to_string(), input[index..].trim_start()),
        None => (input.to_string(), ""),
    }
}

fn split_title_body(text: &str) -> (String, String) {
    let text = text.trim();
    match text.split_once('\n') {
        Some((title, body)) => (title.trim().to_string(), body.trim().to_string()),
        None => (text.to_string(), String::new()),
    }
}

fn clean_title(input: &str) -> String {
    let line = input.lines().next().unwrap_or("").trim();
    cut(line, MAX_TITLE_CHARS)
}

// -- environment -------------------------------------------------------

fn notebook() -> PathBuf {
    PathBuf::from(env_or("PILL_BOT_NOTES_DIR", DEFAULT_NOTEBOOK))
}

fn owner() -> String {
    env_or("PILL_BOT_OWNER", "")
}

fn owner_home() -> PathBuf {
    let fallback = match owner().as_str() {
        "" => "/home/neg".to_string(),
        user => format!("/home/{user}"),
    };
    PathBuf::from(env_or("PILL_BOT_HOME", &fallback))
}

fn is_root() -> bool {
    fs::read_to_string("/proc/self/status")
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

/// Command that runs as the notebook owner. Root drops privileges with
/// `runuser`; a non-root run (tests, a manual `cargo run`) keeps its own user.
fn owner_command(program: &str) -> Command {
    let user = owner();
    let drop = is_root() && !user.is_empty();
    let mut command = if drop {
        let mut command = Command::new(env_or("PILL_BOT_RUNUSER", "runuser"));
        command.arg("-u").arg(&user).arg("--").arg(program);
        command
    } else {
        Command::new(program)
    };
    if drop {
        command.env("HOME", owner_home());
        command.env("USER", &user);
        command.env("LOGNAME", &user);
    }
    command.current_dir(notebook());
    command
}

fn run_owner(program: &str, args: &[&str]) -> Result<Output, String> {
    owner_command(program)
        .args(args)
        .output()
        .map_err(|error| format!("{program}: {error}"))
}

// -- execution ---------------------------------------------------------

pub fn execute(action: &Action) -> String {
    match action {
        Action::Help => HELP.to_string(),
        Action::New { title, body } => create(title, body),
        Action::Show(path) => show(path),
        Action::Append { path, text } => append(path, text),
        Action::Remove { path, confirmed } => remove(path, *confirmed),
        Action::Search(query) => search(query),
        Action::Recent(limit) => recent(*limit),
        Action::Tag(tag) => tag_search(tag),
        Action::Sync => sync(),
    }
}

fn create(title: &str, body: &str) -> String {
    let root = notebook();
    if !root.is_dir() {
        return format!("⚠️ Каталог заметок не найден: {}", root.display());
    }
    let title = clean_title(title);
    if title.is_empty() {
        return HELP.to_string();
    }
    let zk = env_or("PILL_BOT_ZK", "zk");
    let output = match run_owner(
        &zk,
        &["new", "--title", &title, "--print-path", "--no-input"],
    ) {
        Ok(output) => output,
        Err(error) => return format!("⚠️ {error}"),
    };
    if !output.status.success() {
        let error = String::from_utf8_lossy(&output.stderr);
        return format!("⚠️ zk new: {}", cut(error.trim(), 400));
    }
    let printed = String::from_utf8_lossy(&output.stdout);
    let Some(line) = printed
        .lines()
        .rev()
        .map(str::trim)
        .find(|line| !line.is_empty())
    else {
        return "⚠️ zk new не вернул путь заметки.".to_string();
    };
    let path = PathBuf::from(line);
    let path = if path.is_absolute() {
        path
    } else {
        root.join(path)
    };
    let body = body.trim();
    if !body.is_empty() {
        if let Err(error) = append_raw(&path, body) {
            return format!(
                "📝 Заметка создана: {}\n⚠️ тело не дописано: {error}",
                relative(&path)
            );
        }
    }
    format!("📝 Заметка создана: {}\n{title}", relative(&path))
}

fn show(path: &str) -> String {
    let path = match resolve(path) {
        Ok(path) => path,
        Err(error) => return format!("⚠️ {error}"),
    };
    let text = match fs::read_to_string(&path) {
        Ok(text) => text,
        Err(error) => return format!("⚠️ Не читается {}: {error}", relative(&path)),
    };
    let (body, truncated) = cut_with_flag(&text, MAX_SHOW_CHARS);
    let mut out = format!("📄 {}\n\n{}", relative(&path), body.trim_end());
    if truncated {
        out.push_str("\n\n… заметка обрезана, полный текст на хосте.");
    }
    out
}

fn append(path: &str, text: &str) -> String {
    if text.trim().is_empty() {
        return "⚠️ Пустой текст: нечего дописывать.".to_string();
    }
    let path = match resolve(path) {
        Ok(path) => path,
        Err(error) => return format!("⚠️ {error}"),
    };
    let entry = format!("- {} — {}", stamp_now(), text.trim());
    if let Err(error) = append_raw(&path, &entry) {
        return format!("⚠️ Не удалось дописать: {error}");
    }
    format!("✏️ Дописано в {}", relative(&path))
}

fn remove(path: &str, confirmed: bool) -> String {
    let path = match resolve(path) {
        Ok(path) => path,
        Err(error) => return format!("⚠️ {error}"),
    };
    let rel = relative(&path);
    if !confirmed {
        return format!(
            "⚠️ Удалить «{rel}»?\nПодтверди: /note rm {rel} --yes\n(заметка в git — историю можно вернуть)"
        );
    }
    if let Err(error) = fs::remove_file(&path) {
        return format!("⚠️ Не удалось удалить {rel}: {error}");
    }
    format!("🗑️ Удалено: {rel}\nВернуть: git -C {} checkout -- {rel}", notebook().display())
}

fn search(query: &str) -> String {
    let query = query.trim();
    if query.is_empty() {
        return recent(DEFAULT_RECENT);
    }
    if let Some(tag) = query.strip_prefix('#') {
        return tag_search(tag);
    }
    if !notebook().is_dir() {
        return format!("⚠️ Каталог заметок не найден: {}", notebook().display());
    }
    let query = cut(query, MAX_QUERY_CHARS);
    let root = notebook();
    let mut hits: Vec<(String, String)> = Vec::new();
    let lowercase = query.to_lowercase();

    // File-name matches first: a note called `ssh-proxy.md` should be easy to
    // find even when the phrase does not occur in its body.
    for (path, _) in walk_notes() {
        if hits.len() >= MAX_SEARCH_HITS {
            break;
        }
        let name = path
            .file_name()
            .map(|name| name.to_string_lossy().to_lowercase())
            .unwrap_or_default();
        if name.contains(&lowercase) {
            hits.push((relative(&path), "совпадение в имени файла".to_string()));
        }
    }

    let pattern = search_pattern(&query);
    let rg = env_or("PILL_BOT_RG", "rg");
    let root_text = root.to_string_lossy().to_string();
    let mut rg_failed = false;
    match run_owner(
        &rg,
        &[
            "--line-number",
            "--no-heading",
            "--color",
            "never",
            "--smart-case",
            "--max-count",
            "2",
            "--glob",
            "*.md",
            "--glob",
            "!**/_generated/**",
            "--",
            &pattern,
            &root_text,
        ],
    ) {
        // Exit code 1 is "no matches", not a failure: the fallback below only
        // needs to run when ripgrep itself is missing.
        Ok(output) => {
            let body = String::from_utf8_lossy(&output.stdout);
            for line in body.lines() {
                if hits.len() >= MAX_SEARCH_HITS {
                    break;
                }
                let mut fields = line.splitn(3, ':');
                let (Some(file), Some(number), Some(content)) =
                    (fields.next(), fields.next(), fields.next())
                else {
                    continue;
                };
                let path = Path::new(file);
                let rel = relative(path);
                let snippet = format!("{number}: {}", cut(content.trim(), 160));
                if !hits
                    .iter()
                    .any(|(hit_path, hit)| hit_path == &rel && hit == &snippet)
                {
                    hits.push((rel, snippet));
                }
            }
        }
        Err(_) => rg_failed = true,
    }

    if rg_failed || (hits.is_empty() && query.len() > 2) {
        // No ripgrep (or a regex it rejected): a plain case-insensitive scan
        // over the notebook is slower but always available.
        for (path, _) in walk_notes() {
            if hits.len() >= MAX_SEARCH_HITS {
                break;
            }
            let Ok(text) = fs::read_to_string(&path) else {
                continue;
            };
            if let Some((index, line)) = text
                .lines()
                .enumerate()
                .find(|(_, line)| line.to_lowercase().contains(&lowercase))
            {
                let snippet = format!("{}: {}", index + 1, cut(line.trim(), 160));
                let rel = relative(&path);
                if !hits.iter().any(|(hit_path, _)| hit_path == &rel) {
                    hits.push((rel, snippet));
                }
            }
        }
    }

    if hits.is_empty() {
        return format!(
            "🔎 «{}» — ничего не нашёл.\n/notes — последние заметки, /notes recent N — больше.",
            cut(&query, 80)
        );
    }
    let mut out = format!(
        "🔎 «{}» — {}:\n\n",
        cut(&query, 80),
        plural(hits.len(), "совпадение", "совпадения", "совпадений")
    );
    for (index, (path, snippet)) in hits.iter().enumerate() {
        out.push_str(&format!("{}. {path}\n   {snippet}\n", index + 1));
    }
    out.push_str("\n/note show <путь> — открыть заметку.");
    out
}

fn recent(limit: usize) -> String {
    if !notebook().is_dir() {
        return format!("⚠️ Каталог заметок не найден: {}", notebook().display());
    }
    let limit = limit.clamp(1, MAX_RECENT);
    let mut notes = walk_notes();
    notes.sort_by(|left, right| right.1.cmp(&left.1));
    if notes.is_empty() {
        return "📭 В каталоге заметок нет ни одного .md.".to_string();
    }
    let mut out = format!("🗂️ Последние {}:\n\n", notes.len().min(limit));
    for (index, (path, modified)) in notes.iter().take(limit).enumerate() {
        out.push_str(&format!(
            "{}. {} — {}\n   {}\n",
            index + 1,
            relative(path),
            date_of(*modified),
            note_title(path)
        ));
    }
    out.push_str("\n/note show <путь> — открыть, /notes <запрос> — поиск.");
    out
}

fn tag_search(tag: &str) -> String {
    let tag = tag.trim().trim_start_matches('#');
    if tag.is_empty() {
        return HELP.to_string();
    }
    if !notebook().is_dir() {
        return format!("⚠️ Каталог заметок не найден: {}", notebook().display());
    }
    let mut hits = Vec::new();
    for (path, _) in walk_notes() {
        if hits.len() >= MAX_RECENT {
            break;
        }
        let Ok(text) = fs::read_to_string(&path) else {
            continue;
        };
        if has_tag(&text, tag) {
            hits.push(path);
        }
    }
    if hits.is_empty() {
        return format!("🏷️ Тег #{tag}: заметок нет.");
    }
    let mut out = format!(
        "🏷️ Тег #{tag} — {}:\n\n",
        plural(hits.len(), "заметка", "заметки", "заметок")
    );
    for (index, path) in hits.iter().enumerate() {
        out.push_str(&format!("{}. {}\n", index + 1, relative(path)));
    }
    out
}

/// Run `nb` (pull, refresh, commit, push) as the notebook owner. The script is
/// deliberately tolerant — it exits 0 even when the push fails — so the tail of
/// its output is the report: a silent run means nothing changed.
fn sync() -> String {
    let root = notebook();
    if !root.is_dir() {
        return format!("⚠️ Каталог заметок не найден: {}", root.display());
    }
    let nb = env_or(
        "PILL_BOT_NB",
        &owner_home().join(".local/bin/nb").display().to_string(),
    );
    if !Path::new(&nb).exists() {
        return format!("⚠️ nb не найден: {nb}");
    }
    let timeout = env_or("PILL_BOT_NB_TIMEOUT", "90");
    let output = owner_command("timeout")
        .args([timeout.as_str(), nb.as_str()])
        .output()
        .or_else(|_| owner_command(&nb).output());
    let output = match output {
        Ok(output) => output,
        Err(error) => return format!("⚠️ nb не запустился: {error}"),
    };
    let mut report = String::new();
    for stream in [&output.stdout, &output.stderr] {
        let text = String::from_utf8_lossy(stream);
        let text = text.trim_end();
        if !text.is_empty() {
            report.push_str(text);
            report.push('\n');
        }
    }
    let code = output.status.code().unwrap_or(-1);
    let body = if report.trim().is_empty() {
        "без вывода (изменений нет)".to_string()
    } else {
        cut(report.trim(), MAX_SYNC_REPORT)
    };
    if output.status.success() {
        format!("🔄 nb: ok\n\n{body}")
    } else {
        format!("⚠️ nb: exit {code}\n\n{body}")
    }
}

// -- model tools -------------------------------------------------------

pub fn tools_enabled() -> bool {
    !matches!(
        std::env::var("PILL_BOT_NOTES_TOOLS"),
        Ok(value) if value == "0" || value.eq_ignore_ascii_case("false")
    )
}

pub fn tools_json() -> Value {
    Value::Array(vec![
        tool(
            "notes_search",
            "Найти заметки в ~/notes по тексту или имени файла. Возвращает пути и строки.",
            &[("query", "string", "Поисковый запрос.")],
            &["query"],
        ),
        tool(
            "notes_recent",
            "Список последних изменённых заметок.",
            &[("count", "integer", "Сколько заметок вернуть (по умолчанию 10).")],
            &[],
        ),
        tool(
            "notes_read",
            "Прочитать заметку целиком по пути относительно ~/notes.",
            &[("path", "string", "Путь к заметке, например reference/ssh.md.")],
            &["path"],
        ),
        tool(
            "notes_create",
            "Создать новую заметку в ~/notes по шаблону zk. Используй только по прямой просьбе пользователя.",
            &[
                ("title", "string", "Заголовок заметки."),
                ("body", "string", "Текст заметки (может быть пустым)."),
            ],
            &["title"],
        ),
        tool(
            "notes_append",
            "Дописать текст с датой в существующую заметку.",
            &[
                ("path", "string", "Путь к заметке относительно ~/notes."),
                ("text", "string", "Что дописать."),
            ],
            &["path", "text"],
        ),
        tool(
            "notes_sync",
            "Синхронизировать заметки: nb (pull, zk index, commit, push).",
            &[],
            &[],
        ),
    ])
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
                        (
                            "additionalProperties".to_string(),
                            Value::Bool(false),
                        ),
                    ]),
                ),
            ]),
        ),
    ])
}

/// Execute one `tool_call`. Arguments are a JSON object produced by the model;
/// malformed arguments become an error string that the model can read and
/// correct on the next round.
pub fn call_tool(name: &str, arguments: &str) -> String {
    let arguments = json::parse(arguments).unwrap_or(Value::Object(vec![]));
    let result = match name {
        "notes_search" => search(&text_arg(&arguments, "query")),
        "notes_recent" => recent(int_arg(&arguments, "count", DEFAULT_RECENT)),
        "notes_read" => show(&text_arg(&arguments, "path")),
        "notes_create" => create(
            &text_arg(&arguments, "title"),
            &text_arg(&arguments, "body"),
        ),
        "notes_append" => append(
            &text_arg(&arguments, "path"),
            &text_arg(&arguments, "text"),
        ),
        "notes_sync" => sync(),
        other => format!("неизвестный инструмент: {other}"),
    };
    cut(&result, MAX_TOOL_RESULT)
}

fn text_arg(arguments: &Value, key: &str) -> String {
    arguments
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim()
        .to_string()
}

fn int_arg(arguments: &Value, key: &str, fallback: usize) -> usize {
    arguments
        .get(key)
        .and_then(|value| match value {
            Value::Number(number) => Some(*number as i64),
            Value::Str(text) => text.trim().parse().ok(),
            _ => None,
        })
        .map(|value| value.clamp(1, MAX_RECENT as i64) as usize)
        .unwrap_or(fallback)
}

// -- filesystem --------------------------------------------------------

/// Resolve a note path inside the notebook. Rejects absolute paths, `..` and
/// symlinks that leave the tree; adds `.md` when the caller omits it.
fn resolve(requested: &str) -> Result<PathBuf, String> {
    resolve_in(&notebook(), requested)
}

fn resolve_in(root: &Path, requested: &str) -> Result<PathBuf, String> {
    let requested = requested.trim();
    if requested.is_empty() {
        return Err("не указан путь к заметке".to_string());
    }
    if requested.starts_with('/') {
        return Err("путь должен быть относительным, например reference/ssh.md".to_string());
    }
    let canonical_root = fs::canonicalize(root)
        .map_err(|_| format!("каталог заметок не найден: {}", root.display()))?;
    let mut candidate = root.join(requested);
    if candidate.extension().is_none() {
        candidate.set_extension("md");
    }
    let canonical = fs::canonicalize(&candidate)
        .map_err(|_| format!("нет такой заметки: {requested}"))?;
    if !canonical.starts_with(&canonical_root) {
        return Err("путь ведёт за пределы каталога заметок".to_string());
    }
    if !canonical.is_file() {
        return Err(format!("это не файл: {requested}"));
    }
    Ok(canonical)
}

fn append_raw(path: &Path, text: &str) -> Result<(), String> {
    let mut file = fs::OpenOptions::new()
        .append(true)
        .open(path)
        .map_err(|error| error.to_string())?;
    write!(file, "\n{}\n", text.trim_end()).map_err(|error| error.to_string())
}

fn relative(path: &Path) -> String {
    let root = fs::canonicalize(notebook()).unwrap_or_else(|_| notebook());
    path.strip_prefix(&root)
        .unwrap_or(path)
        .display()
        .to_string()
}

/// Every `.md` under the notebook, skipping VCS, zk internals and generated
/// reports. Notes are small, so the walk is cheap and avoids a stale zk index.
fn walk_notes() -> Vec<(PathBuf, SystemTime)> {
    let mut notes = Vec::new();
    walk(&notebook(), &mut notes);
    notes
}

fn walk(directory: &Path, notes: &mut Vec<(PathBuf, SystemTime)>) {
    let Ok(entries) = fs::read_dir(directory) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        if file_type.is_dir() {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with('.') || name == "_generated" || name == "node_modules" {
                continue;
            }
            walk(&path, notes);
        } else if file_type.is_file()
            && path
                .extension()
                .map(|extension| extension == "md")
                .unwrap_or(false)
        {
            let modified = entry
                .metadata()
                .and_then(|metadata| metadata.modified())
                .unwrap_or(UNIX_EPOCH);
            notes.push((path, modified));
        }
    }
}

fn note_title(path: &Path) -> String {
    let Ok(text) = fs::read_to_string(path) else {
        return path
            .file_stem()
            .map(|stem| stem.to_string_lossy().to_string())
            .unwrap_or_default();
    };
    for line in text.lines().take(30) {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("title:") {
            let value = rest.trim().trim_matches('"').trim();
            if !value.is_empty() {
                return cut(value, 80);
            }
        }
    }
    for line in text.lines() {
        if let Some(rest) = line.trim_start().strip_prefix('#') {
            let value = rest.trim_start_matches('#').trim();
            if !value.is_empty() {
                return cut(value, 80);
            }
        }
    }
    path.file_stem()
        .map(|stem| stem.to_string_lossy().to_string())
        .unwrap_or_default()
}

fn date_of(modified: SystemTime) -> String {
    let seconds = modified
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or(0);
    let (year, month, day) = crate::shared::civil_from_days(seconds / 86_400);
    format!("{year:04}-{month:02}-{day:02}")
}

fn has_tag(text: &str, tag: &str) -> bool {
    let tag = tag.to_lowercase();
    let needle = format!("#{tag}");
    let lowercase = text.to_lowercase();
    let mut start = 0;
    while let Some(position) = lowercase.get(start..).and_then(|tail| tail.find(&needle)) {
        let end = start + position + needle.len();
        // `to_lowercase` can change byte lengths, so never slice blindly.
        let boundary = lowercase
            .get(end..)
            .and_then(|tail| tail.chars().next())
            .map(|next| !(next.is_alphanumeric() || next == '-' || next == '_'))
            .unwrap_or(true);
        if boundary {
            return true;
        }
        start = end;
    }
    // Frontmatter tags, both inline (`tags: [ssh, linux]`) and as a YAML list
    // (`tags:` followed by `- linux` items).
    let mut in_frontmatter = false;
    let mut in_tags = false;
    for (index, line) in text.lines().take(60).enumerate() {
        let trimmed = line.trim();
        if index == 0 && trimmed == "---" {
            in_frontmatter = true;
            continue;
        }
        if !in_frontmatter {
            break;
        }
        if trimmed == "---" {
            break;
        }
        if let Some(rest) = trimmed.strip_prefix("tags:") {
            if tag_list_matches(rest, &tag) {
                return true;
            }
            in_tags = true;
            continue;
        }
        if in_tags {
            if let Some(item) = trimmed.strip_prefix('-') {
                if tag_list_matches(item, &tag) {
                    return true;
                }
            } else if !trimmed.is_empty() && !line.starts_with(' ') && !line.starts_with('\t') {
                in_tags = false;
            }
        }
    }
    false
}

fn tag_list_matches(text: &str, tag: &str) -> bool {
    text.to_lowercase()
        .split(|character: char| {
            !(character.is_alphanumeric() || character == '-' || character == '_')
        })
        .any(|word| word == tag)
}

// -- text ---------------------------------------------------------------

fn search_pattern(query: &str) -> String {
    query
        .split_whitespace()
        .take(5)
        .map(escape_regex)
        .collect::<Vec<_>>()
        .join(".*")
}

fn escape_regex(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for character in text.chars() {
        if "\\.^$*+?()[]{}|".contains(character) {
            out.push('\\');
        }
        out.push(character);
    }
    out
}

fn plural<'a>(count: usize, one: &'a str, few: &'a str, many: &'a str) -> &'a str {
    if count % 10 == 1 && count % 100 != 11 {
        one
    } else if (2..=4).contains(&(count % 10)) && !(12..=14).contains(&(count % 100)) {
        few
    } else {
        many
    }
}

fn cut(text: &str, limit: usize) -> String {
    cut_with_flag(text, limit).0
}

/// Truncate on a character boundary; the flag says whether anything was lost.
fn cut_with_flag(text: &str, limit: usize) -> (String, bool) {
    if text.len() <= limit {
        return (text.to_string(), false);
    }
    let mut out = String::new();
    for character in text.chars() {
        if out.len() + character.len_utf8() > limit {
            return (out, true);
        }
        out.push(character);
    }
    (out, false)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn new_action(title: &str, body: &str) -> Action {
        Action::New {
            title: title.to_string(),
            body: body.to_string(),
        }
    }

    #[test]
    fn routes_note_commands() {
        assert_eq!(parse("/note купить хлеб"), Some(new_action("купить хлеб", "")));
        assert_eq!(
            parse("/note заголовок\nвторая строка"),
            Some(new_action("заголовок", "вторая строка"))
        );
        assert_eq!(
            parse("/note show reference/ssh.md"),
            Some(Action::Show("reference/ssh.md".to_string()))
        );
        assert_eq!(
            parse("/note append reference/ssh.md новый факт"),
            Some(Action::Append {
                path: "reference/ssh.md".to_string(),
                text: "новый факт".to_string(),
            })
        );
        assert_eq!(
            parse("/note rm junk.md --yes"),
            Some(Action::Remove {
                path: "junk.md".to_string(),
                confirmed: true,
            })
        );
        assert_eq!(parse("/note"), Some(Action::Help));
        assert_eq!(parse("/notes чат gpt"), Some(Action::Search("чат gpt".to_string())));
        assert_eq!(parse("/notes"), Some(Action::Recent(DEFAULT_RECENT)));
        assert_eq!(parse("/notes recent 3"), Some(Action::Recent(3)));
        assert_eq!(parse("/notes tag linux"), Some(Action::Tag("linux".to_string())));
        assert_eq!(parse("/notes #linux"), Some(Action::Tag("linux".to_string())));
        assert_eq!(parse("/nb"), Some(Action::Sync));
        assert_eq!(parse("/sync@trantor_bot"), Some(Action::Sync));
        assert_eq!(parse("/status"), None);
        assert_eq!(parse("обычный вопрос"), None);
    }

    #[test]
    fn quoted_paths_survive_spaces() {
        assert_eq!(
            parse("/note show \"my notes/день.md\""),
            Some(Action::Show("my notes/день.md".to_string()))
        );
        let (first, rest) = take_arg("\"a b\" tail");
        assert_eq!(first, "a b");
        assert_eq!(rest, "tail");
    }

    #[test]
    fn search_pattern_escapes_regex_metacharacters() {
        assert_eq!(search_pattern("ssh proxy"), "ssh.*proxy");
        assert_eq!(search_pattern("a.b(c)"), "a\\.b\\(c\\)");
    }

    #[test]
    fn tags_match_on_boundaries_and_frontmatter() {
        assert!(has_tag("текст #linux про сеть", "linux"));
        assert!(!has_tag("текст #linuxbrew", "linux"));
        assert!(has_tag("---\ntags: [ssh, linux]\n---\n", "linux"));
        assert!(has_tag("---\ntags:\n  - linux\n---\n", "linux"));
        assert!(!has_tag("---\ntags: [ssh]\n---\n", "linux"));
    }

    #[test]
    fn tool_schema_is_valid_json() {
        let body = tools_json().dump(None);
        let parsed = json::parse(&body).expect("tool schema must be valid json");
        let tools = parsed.as_array().expect("array of tools");
        assert_eq!(tools.len(), 6);
        for tool in tools {
            assert_eq!(tool.get("type").and_then(Value::as_str), Some("function"));
            let function = tool.get("function").expect("function");
            assert!(function
                .get("parameters")
                .and_then(|parameters| parameters.get("type"))
                .and_then(Value::as_str)
                == Some("object"));
        }
    }

    #[test]
    fn truncation_is_utf8_safe() {
        assert_eq!(cut("статус", 5), "ст");
        assert_eq!(cut("ok", 10), "ok");
    }

    #[test]
    fn search_recent_and_tag_read_the_notebook() {
        // The only test that touches PILL_BOT_NOTES_DIR: nothing else reads it
        // in parallel, so the process-wide variable is safe here.
        let root = std::env::temp_dir().join(format!("notes-read-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("reference")).expect("temp notebook");
        fs::write(
            root.join("reference/ssh.md"),
            "---\ntags: [linux, ssh]\n---\n\n# SSH через прокси\nproxy jump\n",
        )
        .expect("note");
        fs::write(root.join("inbox.md"), "# inbox\nproxy notes\n").expect("note");
        std::env::set_var("PILL_BOT_NOTES_DIR", &root);
        std::env::remove_var("PILL_BOT_OWNER");

        let recent = execute(&Action::Recent(5));
        assert!(recent.contains("reference/ssh.md"), "{recent}");
        assert!(recent.contains("inbox.md"), "{recent}");

        let search = execute(&Action::Search("proxy".to_string()));
        assert!(search.contains("reference/ssh.md"), "{search}");
        assert!(search.contains("inbox.md"), "{search}");

        let tag = execute(&Action::Tag("linux".to_string()));
        assert!(tag.contains("reference/ssh.md"), "{tag}");
        assert!(!tag.contains("inbox.md"), "{tag}");

        std::env::remove_var("PILL_BOT_NOTES_DIR");
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn resolve_keeps_paths_inside_the_notebook() {
        let root = std::env::temp_dir().join(format!("notes-resolve-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("reference")).expect("temp notebook");
        fs::write(root.join("reference/ssh.md"), "# ssh").expect("note");
        fs::write(root.join("junk.markdown"), "x").expect("note");
        std::os::unix::fs::symlink("/etc/passwd", root.join("escape.md")).expect("symlink");

        assert_eq!(
            resolve_in(&root, "reference/ssh").expect("extension added"),
            fs::canonicalize(root.join("reference/ssh.md")).expect("canonical")
        );
        assert_eq!(
            resolve_in(&root, "junk.markdown").expect("existing extension kept"),
            fs::canonicalize(root.join("junk.markdown")).expect("canonical")
        );
        assert_eq!(
            resolve_in(&root, "/etc/passwd"),
            Err("путь должен быть относительным, например reference/ssh.md".to_string())
        );
        assert!(resolve_in(&root, "../outside.md").is_err());
        assert!(resolve_in(&root, "escape.md").is_err());

        let _ = fs::remove_dir_all(&root);
    }
}
