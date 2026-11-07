//! Notes for the monitoring bot.
//!
//! The chat is the phone-side interface to the `~/notes` zk notebook: create,
//! show, append, lexical and semantic search, list, tag lookup, delete and the
//! `nb` sync script (pull, `zk index`, commit, push). The commands are
//! deterministic and work without the model; the same operations are also
//! exposed to the local model as OpenAI tool calls (see `ask.rs`), so free text
//! like "запиши в заметки …" and explicit commands share one implementation.
//! Semantic search shells out to the user's `rag-search` (qwen3-embedding +
//! optional bge reranker) and reads its SQLite index without refreshing it.
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
//!   PILL_BOT_RG            ripgrep binary (default `rg` from PATH)
//!   PILL_BOT_RAG           semantic-search CLI (default ~/.local/bin/rag-search)
//!   PILL_BOT_RAG_INDEX     embedding index watched for staleness
//!                          (default ~/.local/share/rag-notes/index.sqlite)
//!   PILL_BOT_RAG_N         semantic hits to return (default 5)
//!   PILL_BOT_RAG_TIMEOUT   seconds before `rag-search` is killed (default 120)
//!   PILL_BOT_RUNUSER       privilege drop helper (default `runuser`)
//!   PILL_BOT_NB_TIMEOUT    seconds before `nb` is killed (default 90)
//!   PILL_BOT_NOTES_TOOLS=0 disable the model tools
//!
//! New notes are written by the bot itself rather than by `zk new`: the
//! notebook's filename template uses `{{slug}}`, which zk 0.15.7 does not
//! provide, so `zk new` would create an empty `.md` name. The bot slugifies
//! the title (Cyrillic transliterated, like the rest of the notebook),
//! renders `.zk/templates/note.md` and fills in fresh frontmatter.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::shared::json::{self, Value};
use crate::{env_or, stamp_now, Api};

const DEFAULT_NOTEBOOK: &str = "/home/neg/notes";
const DEFAULT_RECENT: usize = 10;
const MAX_RECENT: usize = 25;
/// The title becomes a filename and a heading; the limit is in bytes because
/// `cut` works on byte offsets (120 bytes ≈ 60 Cyrillic characters).
const MAX_TITLE_BYTES: usize = 120;
const MAX_QUERY_CHARS: usize = 200;
const MAX_SEARCH_HITS: usize = 8;
/// Telegram splits long answers anyway, but a whole book would become a dozen
/// messages; the cap keeps one note readable on a phone.
const MAX_SHOW_CHARS: usize = 12_000;
/// Tool output goes back into a 4B model's context.
const MAX_TOOL_RESULT: usize = 6_000;
const MAX_SYNC_REPORT: usize = 3_000;

/// One `getUpdates` loop serves callbacks too, so a second `/nb` must not
/// start a concurrent git operation in the same repository.
static SYNCING: AtomicBool = AtomicBool::new(false);

const HELP: &str = "📝 Заметки (~/notes):\n\n\
/note <текст> — новая заметка, заголовок из первой строки.\n\
/note new <заголовок> — пустая заметка по шаблону zk.\n\
/note show <путь> — показать заметку.\n\
/note append <путь> <текст> — дописать с датой.\n\
/note rm <путь> --yes — удалить; несинхронизированную — ещё и --force.\n\
/notes <запрос> — поиск по тексту и именам; /notes — последние.\n\
/notes find <запрос> — семантический поиск (RAG, эмбеддинги).\n\
/notes recent [N] — последние N заметок.\n\
/notes tag <тег> — заметки с тегом.\n\
/nb — синхронизация: pull, zk index, commit, push.";

/// One parsed notes command. Owned strings keep the routing free of lifetimes:
/// the model-tool path builds actions from JSON, not from the message text.
#[derive(Debug, Clone, PartialEq)]
pub enum Action {
    Help,
    New {
        title: String,
        body: String,
    },
    Show(String),
    Append {
        path: String,
        text: String,
    },
    Remove {
        path: String,
        confirmed: bool,
        force: bool,
    },
    Search(String),
    Semantic(String),
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
            if SYNCING.swap(true, Ordering::SeqCst) {
                crate::ask::deliver(
                    api,
                    chat_id,
                    "⏳ Синхронизация уже идёт — дождись ответа.",
                    reply_to,
                    None,
                );
                return true;
            }
            // A push can wait on the network for a minute; the poll loop must
            // keep answering callback presses while it runs.
            let thread_api = api.clone();
            let thread_chat = chat_id.to_string();
            let spawned = std::thread::Builder::new()
                .name("telegram-notes-sync".into())
                .spawn(move || {
                    let reply = sync();
                    SYNCING.store(false, Ordering::SeqCst);
                    crate::ask::deliver(&thread_api, &thread_chat, &reply, reply_to, None);
                });
            if spawned.is_err() {
                SYNCING.store(false, Ordering::SeqCst);
                eprintln!("notes: cannot spawn the sync thread");
                crate::ask::deliver(
                    api,
                    chat_id,
                    "⚠️ Не удалось запустить синхронизацию.",
                    reply_to,
                    None,
                );
            }
        }
        // The embedding call can take seconds and its timeout is minutes; keep
        // it out of the getUpdates loop for the same reason as `/nb`.
        Action::Semantic(query) => {
            let thread_api = api.clone();
            let thread_chat = chat_id.to_string();
            let spawned = std::thread::Builder::new()
                .name("telegram-notes-semantic".into())
                .spawn(move || {
                    let reply = semantic_search(&query);
                    crate::ask::deliver(&thread_api, &thread_chat, &reply, reply_to, None);
                });
            if spawned.is_err() {
                eprintln!("notes: cannot spawn the semantic-search thread");
                crate::ask::deliver(
                    api,
                    chat_id,
                    "⚠️ Не удалось запустить семантический поиск.",
                    reply_to,
                    None,
                );
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
                let flags: Vec<&str> = extra.split_whitespace().collect();
                Action::Remove {
                    path,
                    confirmed: flags
                        .iter()
                        .any(|word| matches!(*word, "--yes" | "-y" | "да")),
                    force: flags.iter().any(|word| matches!(*word, "--force" | "-f")),
                }
            }
        }
        // Anything else after `/note` is a quick capture: the first line
        // becomes the title and every remaining byte lands in the body, so a
        // long one-liner is not silently truncated.
        _ => {
            let (title, body) = quick_capture(rest);
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
        // Semantic search over the embedding index (rag-search).
        "find" | "semantic" | "rag" | "семантика" | "найти" => {
            let query = tail.trim().to_string();
            if query.is_empty() {
                Action::Help
            } else {
                Action::Semantic(query)
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

/// `/note <text>`: the first line is the heading, but anything that does not
/// fit into the 120-byte title limit is kept in the body instead of being
/// dropped. The same applies to the rest of a long first line.
fn quick_capture(text: &str) -> (String, String) {
    let text = text.trim();
    let first_end = text.find('\n').unwrap_or(text.len());
    let first = text[..first_end].trim_end();
    let rest = text[first_end..].trim();
    let (raw_title, truncated) = cut_with_flag(first, MAX_TITLE_BYTES);
    let title = raw_title.trim().to_string();
    if !truncated {
        return (title, rest.to_string());
    }
    let mut body = first[raw_title.len()..].trim_start().to_string();
    if !rest.is_empty() {
        if !body.is_empty() {
            body.push('\n');
        }
        body.push_str(rest);
    }
    (title, body.trim().to_string())
}

fn clean_title(input: &str) -> String {
    let line = input.lines().next().unwrap_or("").trim();
    cut(line, MAX_TITLE_BYTES)
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

/// Like `run_owner`, but under coreutils `timeout`: a stuck ollama/reranker
/// must not pin a worker forever. Falls back to an untimed run when `timeout`
/// itself is missing.
fn run_owner_timeout(program: &str, seconds: &str, args: &[&str]) -> Result<Output, String> {
    match owner_command("timeout")
        .arg(seconds)
        .arg(program)
        .args(args)
        .output()
    {
        Ok(output) => Ok(output),
        Err(_) => run_owner(program, args),
    }
}

// -- execution ---------------------------------------------------------

pub fn execute(action: &Action) -> String {
    match action {
        Action::Help => HELP.to_string(),
        Action::New { title, body } => create(title, body),
        Action::Show(path) => show(path),
        Action::Append { path, text } => append(path, text),
        Action::Remove {
            path,
            confirmed,
            force,
        } => remove(path, *confirmed, *force),
        Action::Search(query) => search(query),
        Action::Semantic(query) => semantic_search(query),
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
    // `zk new` cannot name the file here: this notebook's config uses the
    // `{{slug}}` variable, which zk 0.15.7 does not provide (it renders an
    // empty name). The bot therefore writes the note itself, keeping the
    // notebook's own template and filling in fresh frontmatter.
    let slug = slugify(&title);
    let mut path = root.join(format!("{slug}.md"));
    let mut counter = 2;
    while path.exists() {
        if counter > 50 {
            return format!("⚠️ Не удалось подобрать имя для «{title}».");
        }
        path = root.join(format!("{slug}-{counter}.md"));
        counter += 1;
    }
    let template = fs::read_to_string(root.join(".zk/templates/note.md")).ok();
    let mut text = render_note(template.as_deref(), &title);
    let body = body.trim();
    if !body.is_empty() {
        text.push('\n');
        text.push_str(body);
        text.push('\n');
    }
    if let Err(error) = write_note_file(&path, &text) {
        return format!("⚠️ Не удалось создать заметку: {error}");
    }
    format!("📝 Заметка создана: {}\n{title}", relative(&path))
}

/// Write a brand-new note as the notebook owner. The unit runs as root, so a
/// plain write would leave a root-owned file; the file is chowned to the owner
/// and removed again if that fails.
fn write_note_file(path: &Path, text: &str) -> Result<(), String> {
    fs::write(path, text).map_err(|error| error.to_string())?;
    let user = owner();
    if !is_root() || user.is_empty() {
        return Ok(());
    }
    let status = Command::new("chown")
        .arg(format!("{user}:"))
        .arg(path)
        .status()
        .map_err(|error| format!("chown: {error}"))?;
    if status.success() {
        return Ok(());
    }
    let _ = fs::remove_file(path);
    Err(format!("chown {user} не удался"))
}

fn render_note(template: Option<&str>, title: &str) -> String {
    let created = date_format("+%Y-%m-%dT%H:%M:%S%:z");
    let day = date_format("+%Y-%m-%d");
    let uuid = date_format("+%Y%m%d%H%M%S");
    let title_yaml = yaml_escape(title);
    let base = match template {
        // The raw title goes into the body heading; `refresh_frontmatter`
        // re-renders the `title:` line with YAML escaping.
        Some(template) => template.replace("{{title}}", title),
        None => format!(
            "---\ncreated: \"{created}\"\ntitle: \"{title_yaml}\"\ndate: {day}\nuuid: {uuid}\ntags: []\ntype:\n---\n\n# {title}\n"
        ),
    };
    refresh_frontmatter(&base, &title_yaml, &created, &day, &uuid)
}

/// The notebook template hardcodes the creation date and uuid; replace those
/// in the frontmatter block so every note gets its own.
fn refresh_frontmatter(text: &str, title: &str, created: &str, day: &str, uuid: &str) -> String {
    let Some(rest) = text.strip_prefix("---\n") else {
        return text.to_string();
    };
    let Some(end) = rest.find("\n---") else {
        return text.to_string();
    };
    let (front, tail) = rest.split_at(end);
    let lines: Vec<String> = front
        .lines()
        .map(|line| {
            let key = line
                .split_once(':')
                .map(|(key, _)| key.trim())
                .unwrap_or("");
            match key {
                "title" => format!("title: \"{title}\""),
                "created" => format!("created: \"{created}\""),
                "date" => format!("date: {day}"),
                "uuid" => format!("uuid: {uuid}"),
                _ => line.to_string(),
            }
        })
        .collect();
    format!(
        "---\n{}\n{}",
        lines.join("\n"),
        tail.trim_start_matches('\n')
    )
}

fn yaml_escape(text: &str) -> String {
    text.replace('\\', "\\\\").replace('"', "\\\"")
}

/// Lowercase, no spaces, ASCII: the notebook's filenames are transliterated
/// slugs (`spor-o-depressii.md`), so Russian titles need the same treatment.
fn slugify(title: &str) -> String {
    let mut words: Vec<String> = Vec::new();
    let mut current = String::new();
    for character in title.chars() {
        let lower = character.to_lowercase().next().unwrap_or(character);
        if lower.is_ascii_alphanumeric() {
            current.push(lower);
        } else if let Some(latin) = transliterate(lower) {
            current.push_str(latin);
        } else if !current.is_empty() {
            words.push(std::mem::take(&mut current));
        }
    }
    if !current.is_empty() {
        words.push(current);
    }
    let slug = cut(&words.join("-"), 60);
    let slug = slug.trim_matches('-').to_string();
    if slug.is_empty() {
        "note".to_string()
    } else {
        slug
    }
}

fn transliterate(character: char) -> Option<&'static str> {
    Some(match character {
        'а' => "a",
        'б' => "b",
        'в' => "v",
        'г' => "g",
        'д' => "d",
        'е' | 'ё' => "e",
        'ж' => "zh",
        'з' => "z",
        'и' => "i",
        'й' => "y",
        'к' => "k",
        'л' => "l",
        'м' => "m",
        'н' => "n",
        'о' => "o",
        'п' => "p",
        'р' => "r",
        'с' => "s",
        'т' => "t",
        'у' => "u",
        'ф' => "f",
        'х' => "kh",
        'ц' => "ts",
        'ч' => "ch",
        'ш' => "sh",
        'щ' => "shch",
        'ъ' | 'ь' => "",
        'ы' => "y",
        'э' => "e",
        'ю' => "yu",
        'я' => "ya",
        'і' => "i",
        'ї' => "yi",
        'є' => "ye",
        'ґ' => "g",
        _ => return None,
    })
}

fn date_format(format: &str) -> String {
    for candidate in ["/run/current-system/sw/bin/date", "date"] {
        if let Ok(output) = Command::new(candidate).arg(format).output() {
            if output.status.success() {
                return String::from_utf8_lossy(&output.stdout).trim().to_string();
            }
        }
    }
    String::new()
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

#[derive(Debug, PartialEq)]
enum RemoveCheck {
    NeedConfirm,
    Untracked,
    Ready,
}

/// A note created on the phone is untracked until `/nb` commits it; deleting
/// it with the usual confirmation would destroy the only copy while promising
/// a `git checkout` that cannot work. `--force` is the explicit way out.
fn remove_check(tracked: bool, confirmed: bool, force: bool) -> RemoveCheck {
    if !confirmed {
        RemoveCheck::NeedConfirm
    } else if !tracked && !force {
        RemoveCheck::Untracked
    } else {
        RemoveCheck::Ready
    }
}

fn is_tracked(rel: &str) -> bool {
    run_owner("git", &["ls-files", "--error-unmatch", "--", rel])
        .map(|output| output.status.success())
        .unwrap_or(false)
}

fn remove(path: &str, confirmed: bool, force: bool) -> String {
    let path = match resolve(path) {
        Ok(path) => path,
        Err(error) => return format!("⚠️ {error}"),
    };
    let rel = relative(&path);
    let tracked = is_tracked(&rel);
    match remove_check(tracked, confirmed, force) {
        RemoveCheck::NeedConfirm => {
            format!("⚠️ Удалить «{rel}»?\nПодтверди: /note rm \"{rel}\" --yes")
        }
        RemoveCheck::Untracked => format!(
            "⚠️ «{rel}» ещё не в git (не было /nb): удаление безвозвратно.\n\
Если точно: /note rm \"{rel}\" --yes --force"
        ),
        RemoveCheck::Ready => {
            if let Err(error) = fs::remove_file(&path) {
                return format!("⚠️ Не удалось удалить {rel}: {error}");
            }
            if tracked {
                format!(
                    "🗑️ Удалено: {rel}\nВернуть: git -C {} checkout -- \"{rel}\"",
                    notebook().display()
                )
            } else {
                format!("🗑️ Удалено безвозвратно (не была в git): {rel}")
            }
        }
    }
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
            "🔎 «{}» — ничего не нашёл.\n/notes — последние, /notes find «{}» — семантический поиск.",
            cut(&query, 80),
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

/// Semantic search over the embedding index built by `rag-search`.
///
/// The index lives in the user's home and is refreshed by hand
/// (`rag-search index`, ~5 minutes), so the bot only reads it. The reranker is
/// used when it is already running; otherwise the search asks for cosine-only
/// results instead of starting a llama-server, which would need a writable log
/// next to the index.
fn semantic_search(query: &str) -> String {
    let query = query.trim();
    if query.is_empty() {
        return HELP.to_string();
    }
    let rag = env_or(
        "PILL_BOT_RAG",
        &owner_home()
            .join(".local/bin/rag-search")
            .display()
            .to_string(),
    );
    if !Path::new(&rag).exists() {
        return format!("⚠️ rag-search не найден: {rag}\n/notes <запрос> — обычный поиск.");
    }
    let count = env_or("PILL_BOT_RAG_N", "5")
        .parse::<usize>()
        .unwrap_or(5)
        .clamp(1, 10);
    // Ask for twice as many: the embedding index stores chunks, so one note
    // can fill the whole answer with near-identical fragments.
    let requested = (count * 2).clamp(1, 10).to_string();
    let mut args = vec!["search", "-n", requested.as_str()];
    if !reranker_running(&rag) {
        args.push("--no-rerank");
    }
    args.push(query);
    let timeout = env_or("PILL_BOT_RAG_TIMEOUT", "120");
    let output = match run_owner_timeout(&rag, &timeout, &args) {
        Ok(output) => output,
        Err(error) => return format!("⚠️ RAG не запустился: {error}"),
    };
    if output.status.code() == Some(124) {
        return format!("⚠️ RAG не ответил за {timeout} с — ollama или реранкер завис.");
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    if !output.status.success() {
        let error = if stderr.trim().is_empty() {
            stdout.trim()
        } else {
            stderr.trim()
        };
        return format!("⚠️ RAG: {}", cut(error, 500));
    }
    let body = compact_rag(stdout.trim(), count);
    if body.is_empty() {
        return format!("🧠 «{}» — RAG ничего не нашёл.", cut(query, 80));
    }
    let files = body
        .lines()
        .filter(|line| rag_header_path(line).is_some())
        .count();
    let mut reply = String::new();
    if let Some(warning) = index_warning() {
        reply.push_str(&warning);
        reply.push_str("\n\n");
    }
    let count_label = rag_count_label(files);
    reply.push_str(&format!(
        "🧠 RAG: «{}»{}\n\n{}",
        cut(query, 80),
        count_label,
        cut(&body, 8000)
    ));
    reply
}

/// ` — 5 файлов`; empty when the tool's output could not be split into files.
fn rag_count_label(files: usize) -> String {
    if files == 0 {
        return String::new();
    }
    format!(" — {files} {}", plural(files, "файл", "файла", "файлов"))
}

/// Keep one result per file: the index stores chunks, and a single note with a
/// long tag block would otherwise fill the whole answer.
fn compact_rag(body: &str, limit: usize) -> String {
    let mut blocks: Vec<(String, String)> = Vec::new();
    let mut current: Option<(String, String)> = None;
    for line in body.lines() {
        if let Some(path) = rag_header_path(line) {
            if let Some((path, block)) = current.take() {
                blocks.push((path, block));
            }
            current = Some((path, format!("{line}\n")));
        } else if let Some((_, block)) = current.as_mut() {
            block.push_str(line);
            block.push('\n');
        }
        // The tool's own header (`Search «…» — N results`) is dropped: the
        // reply gets its own header and N counts chunks, not files.
    }
    if let Some((path, block)) = current {
        blocks.push((path, block));
    }
    if blocks.is_empty() {
        return body.to_string();
    }
    let mut seen: Vec<String> = Vec::new();
    let mut out = String::new();
    let mut kept = 0;
    for (path, block) in blocks {
        if seen.contains(&path) {
            continue;
        }
        seen.push(path);
        let kept_block = renumber_rag_block(&block, kept + 1);
        out.push_str(kept_block.trim_end());
        out.push_str("\n\n");
        kept += 1;
        if kept >= limit {
            break;
        }
    }
    out.trim_end().to_string()
}

fn renumber_rag_block(block: &str, number: usize) -> String {
    let block = block.trim_start();
    match block.split_once(char::is_whitespace) {
        Some((_, rest)) => format!("#{number} {rest}"),
        None => block.to_string(),
    }
}

/// Path from a `rag-search` result header, e.g.
/// `#1  [cos 0.60]  rerank: -1.7  reference/ssh.md  (SSH setup)`.
/// Files without a frontmatter title have no `(title)` suffix, so the whole
/// remainder after the score is the path.
fn rag_header_path(line: &str) -> Option<String> {
    let trimmed = line.trim_start();
    let number = trimmed.strip_prefix('#')?;
    if !number.chars().next()?.is_ascii_digit() {
        return None;
    }
    let rest = if let Some((_, after)) = trimmed.split_once("rerank:") {
        after.trim_start().split_once("  ")?.1
    } else {
        trimmed.split_once(']')?.1.trim_start()
    };
    let path = rest
        .rsplit_once("  (")
        .map(|(path, _)| path)
        .unwrap_or(rest)
        .trim();
    if path.is_empty() {
        None
    } else {
        Some(path.to_string())
    }
}

fn reranker_running(rag: &str) -> bool {
    run_owner_timeout(rag, "20", &["status"])
        .ok()
        .filter(|output| output.status.success())
        .map(|output| String::from_utf8_lossy(&output.stdout).contains("Reranker: running"))
        .unwrap_or(false)
}

/// The embedding index is refreshed by hand; warn when it predates the notes
/// the user is likely to search for.
fn index_warning() -> Option<String> {
    let path = PathBuf::from(env_or(
        "PILL_BOT_RAG_INDEX",
        &owner_home()
            .join(".local/share/rag-notes/index.sqlite")
            .display()
            .to_string(),
    ));
    let modified = fs::metadata(&path)
        .and_then(|metadata| metadata.modified())
        .ok()?;
    let age = SystemTime::now()
        .duration_since(modified)
        .map(|age| age.as_secs() / 86_400)
        .unwrap_or(0);
    if age < 30 {
        return None;
    }
    Some(format!(
        "⚠️ RAG-индекс от {}, заметки новее могут не находиться (rag-search index).",
        date_of(modified)
    ))
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
/// deliberately tolerant — it exits 0 even when a git step fails — so the
/// verdict has to look at the output too, and the tail (not the head) is what
/// matters: git prints the failure last.
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
    let report = report.trim();
    let failed = nb_report_failed(output.status.success(), code, report);
    let body = if report.is_empty() {
        if failed {
            "вывода нет".to_string()
        } else {
            "без вывода (изменений нет)".to_string()
        }
    } else {
        tail(report, MAX_SYNC_REPORT)
    };
    if failed {
        format!("⚠️ nb: похоже, не всё прошло (exit {code}) — проверь вывод\n\n{body}")
    } else {
        format!("🔄 nb: ok\n\n{body}")
    }
}

/// `nb` ignores every git status; a successful exit therefore does not mean
/// that the pull, commit or push worked.
fn nb_report_failed(success: bool, code: i32, report: &str) -> bool {
    if !success || code == 124 {
        return true;
    }
    let lower = report.to_lowercase();
    ["fatal:", "error:", "conflict (", "automatic merge failed"]
        .iter()
        .any(|needle| lower.contains(needle))
}

/// Last `limit` bytes on a character boundary, with a marker when shortened.
fn tail(text: &str, limit: usize) -> String {
    if text.len() <= limit {
        return text.to_string();
    }
    let mut start = text.len() - limit;
    while start < text.len() && !text.is_char_boundary(start) {
        start += 1;
    }
    format!("…{}", &text[start..])
}

// -- model tools -------------------------------------------------------

pub fn tools_enabled() -> bool {
    !matches!(
        std::env::var("PILL_BOT_NOTES_TOOLS"),
        Ok(value) if value == "0" || value.eq_ignore_ascii_case("false")
    )
}

/// Read-only tools are always available; the write tools are exposed only when
/// the user's message asks for a write. A 4B model that has just read a note
/// can otherwise be talked into "adding" something by the note itself.
pub fn write_intent(question: &str) -> bool {
    const VERBS: &[&str] = &[
        "запиши",
        "записать",
        "создай",
        "создать",
        "добавь",
        "добавить",
        "допиши",
        "дописать",
        "сохрани",
        "сохранить",
        "занеси",
        "внеси",
        "синхронизируй",
        "синхронизировать",
        "сделай заметк",
        "создай заметк",
        "новую заметк",
        "обнови заметк",
        "save",
        "append",
        "sync notes",
    ];
    let question = question.to_lowercase();
    VERBS.iter().any(|verb| question.contains(verb))
}

pub fn tools_json(write_allowed: bool) -> Value {
    let mut tools = vec![
        tool(
            "notes_search",
            "Найти заметки в ~/notes по точным словам или имени файла. Быстро, но не понимает синонимы.",
            &[("query", "string", "Поисковый запрос.")],
            &["query"],
        ),
        tool(
            "notes_semantic",
            "Семантический поиск заметок по смыслу (RAG на эмбеддингах). Медленнее обычного поиска; используй, когда точных слов нет или запрос сформулирован иначе.",
            &[("query", "string", "Что найти по смыслу.")],
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
    ];
    if write_allowed {
        tools.push(tool(
            "notes_create",
            "Создать новую заметку в ~/notes по шаблону zk. Используй только по прямой просьбе пользователя.",
            &[
                ("title", "string", "Заголовок заметки."),
                ("body", "string", "Текст заметки (может быть пустым)."),
            ],
            &["title"],
        ));
        tools.push(tool(
            "notes_append",
            "Дописать текст с датой в существующую заметку.",
            &[
                ("path", "string", "Путь к заметке относительно ~/notes."),
                ("text", "string", "Что дописать."),
            ],
            &["path", "text"],
        ));
        tools.push(tool(
            "notes_sync",
            "Синхронизировать заметки: nb (pull, zk index, commit, push).",
            &[],
            &[],
        ));
    }
    Value::Array(tools)
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
                        ("additionalProperties".to_string(), Value::Bool(false)),
                    ]),
                ),
            ]),
        ),
    ])
}

/// Tool-side read: unlike `/note show`, the model must know when it got only
/// a prefix, otherwise it will confidently answer about a note it has not seen
/// in full. The header is rendered before the body so the final result cap
/// cannot cut the notice off.
fn read_note_for_model(path: &str) -> String {
    let path = match resolve(path) {
        Ok(path) => path,
        Err(error) => return format!("⚠️ {error}"),
    };
    let text = match fs::read_to_string(&path) {
        Ok(text) => text,
        Err(error) => return format!("⚠️ Не читается {}: {error}", relative(&path)),
    };
    let total = text.chars().count();
    let budget = MAX_TOOL_RESULT.saturating_sub(400);
    let (body, truncated) = cut_with_flag(&text, budget);
    if truncated {
        format!(
            "📄 {} — показаны первые {} из {} символов (заметка обрезана)\n\n{}",
            relative(&path),
            body.chars().count(),
            total,
            body
        )
    } else {
        format!("📄 {}\n\n{}", relative(&path), body)
    }
}

/// Execute one `tool_call`. Arguments are a JSON object produced by the model;
/// malformed arguments become an error string that the model can read and
/// correct on the next round. `write_allowed` is re-checked here because a
/// server is free to return a tool call that was not in the offered list.
pub fn call_tool(name: &str, arguments: &str, write_allowed: bool) -> String {
    if !write_allowed && matches!(name, "notes_create" | "notes_append" | "notes_sync") {
        return "⚠️ запись в заметки недоступна: пользователь не просил их менять".to_string();
    }
    let arguments = json::parse(arguments).unwrap_or(Value::Object(vec![]));
    let result = match name {
        "notes_search" => search(&text_arg(&arguments, "query")),
        "notes_semantic" => semantic_search(&text_arg(&arguments, "query")),
        "notes_recent" => recent(int_arg(&arguments, "count", DEFAULT_RECENT)),
        "notes_read" => read_note_for_model(&text_arg(&arguments, "path")),
        "notes_create" => create(
            &text_arg(&arguments, "title"),
            &text_arg(&arguments, "body"),
        ),
        "notes_append" => append(&text_arg(&arguments, "path"), &text_arg(&arguments, "text")),
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
    let canonical =
        fs::canonicalize(&candidate).map_err(|_| format!("нет такой заметки: {requested}"))?;
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
        assert_eq!(
            parse("/note купить хлеб"),
            Some(new_action("купить хлеб", ""))
        );
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
                force: false,
            })
        );
        assert_eq!(
            parse("/note rm junk.md --yes --force"),
            Some(Action::Remove {
                path: "junk.md".to_string(),
                confirmed: true,
                force: true,
            })
        );
        assert_eq!(parse("/note"), Some(Action::Help));
        assert_eq!(
            parse("/notes чат gpt"),
            Some(Action::Search("чат gpt".to_string()))
        );
        assert_eq!(parse("/notes"), Some(Action::Recent(DEFAULT_RECENT)));
        assert_eq!(parse("/notes recent 3"), Some(Action::Recent(3)));
        assert_eq!(
            parse("/notes tag linux"),
            Some(Action::Tag("linux".to_string()))
        );
        assert_eq!(
            parse("/notes #linux"),
            Some(Action::Tag("linux".to_string()))
        );
        assert_eq!(
            parse("/notes find как настроить прокси"),
            Some(Action::Semantic("как настроить прокси".to_string()))
        );
        assert_eq!(parse("/notes find"), Some(Action::Help));
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
        let body = tools_json(true).dump(None);
        let parsed = json::parse(&body).expect("tool schema must be valid json");
        let tools = parsed.as_array().expect("array of tools");
        assert_eq!(tools.len(), 7);
        for tool in tools {
            assert_eq!(tool.get("type").and_then(Value::as_str), Some("function"));
            let function = tool.get("function").expect("function");
            assert!(
                function
                    .get("parameters")
                    .and_then(|parameters| parameters.get("type"))
                    .and_then(Value::as_str)
                    == Some("object")
            );
        }
        // Read-only questions must not expose create/append/sync to the model.
        let read_only = tools_json(false);
        let tools = read_only.as_array().expect("array of tools");
        assert_eq!(tools.len(), 4);
        let names: Vec<&str> = tools
            .iter()
            .filter_map(|tool| tool.get("function"))
            .filter_map(|function| function.get("name"))
            .filter_map(Value::as_str)
            .collect();
        assert_eq!(
            names,
            vec![
                "notes_search",
                "notes_semantic",
                "notes_recent",
                "notes_read"
            ]
        );
    }

    #[test]
    fn write_tools_are_refused_without_intent() {
        let refused = call_tool("notes_create", r#"{"title":"x"}"#, false);
        assert!(refused.contains("недоступна"), "{refused}");
        let refused = call_tool("notes_append", r#"{"path":"x.md","text":"y"}"#, false);
        assert!(refused.contains("недоступна"), "{refused}");
        let refused = call_tool("notes_sync", "{}", false);
        assert!(refused.contains("недоступна"), "{refused}");
    }

    #[test]
    fn write_intent_needs_a_write_verb() {
        assert!(write_intent("запиши в заметки про прокси"));
        assert!(write_intent("создай заметку о встрече"));
        assert!(write_intent("допиши в reference/ssh.md"));
        assert!(write_intent("сохрани мысль"));
        assert!(!write_intent("найди в заметках про прокси"));
        assert!(!write_intent("что я писал про ssh?"));
        assert!(!write_intent("покажи последние заметки"));
    }

    #[test]
    fn quick_capture_does_not_drop_a_long_line() {
        let text = "длинная строка ".repeat(40);
        let (title, body) = quick_capture(&text);
        assert!(title.len() <= MAX_TITLE_BYTES);
        assert!(!body.is_empty());
        // Every character of the input survives between title and body.
        let rejoined = format!("{title}{body}").replace(' ', "");
        let original = text.replace(' ', "");
        assert!(original.ends_with(&rejoined), "{title} / {body}");
        assert!(original.contains(&body.replace(' ', "")));
    }

    #[test]
    fn multiline_capture_keeps_the_first_line_as_title() {
        let (title, body) = quick_capture("заголовок\nпервая строка\nвторая");
        assert_eq!(title, "заголовок");
        assert_eq!(body, "первая строка\nвторая");
    }

    #[test]
    fn removing_an_untracked_note_requires_force() {
        assert_eq!(remove_check(true, false, false), RemoveCheck::NeedConfirm);
        assert_eq!(remove_check(false, false, false), RemoveCheck::NeedConfirm);
        assert_eq!(remove_check(false, true, false), RemoveCheck::Untracked);
        assert_eq!(remove_check(true, true, false), RemoveCheck::Ready);
        assert_eq!(remove_check(false, true, true), RemoveCheck::Ready);
    }

    #[test]
    fn nb_verdict_sees_errors_in_a_zero_exit_run() {
        assert!(nb_report_failed(
            true,
            0,
            "fatal: could not read from remote"
        ));
        assert!(nb_report_failed(true, 0, "error: failed to push some refs"));
        assert!(nb_report_failed(false, 1, ""));
        assert!(nb_report_failed(true, 124, ""));
        assert!(!nb_report_failed(true, 0, "Already up to date."));
        assert!(!nb_report_failed(true, 0, "create mode 100644 note.md"));
    }

    #[test]
    fn tail_keeps_the_end_and_stays_utf8() {
        let text = "начало\nошибка в конце";
        let tailed = tail(text, 10);
        assert!(tailed.starts_with('…'));
        assert!(tailed.ends_with("конце"));
        assert_eq!(tail("short", 10), "short");
    }

    #[test]
    fn rag_results_are_deduplicated_per_file() {
        let body = "Search «q» — 5 results:\n\n\
#1  [cos 0.60]  rerank: -1.0  a.md  (A)\n    snippet a\n\n\
#2  [cos 0.55]  rerank: -2.0  a.md  (A)\n    snippet a again\n\n\
#3  [cos 0.52]  rerank: -2.5  list.txt\n    snippet list\n\n\
#4  [cos 0.51]  rerank: -2.6  list.txt\n    snippet list again\n\n\
#5  [cos 0.50]  rerank: -3.0  b.md  (B)\n    snippet b";
        let out = compact_rag(body, 5);
        assert_eq!(out.matches("a.md").count(), 1, "{out}");
        assert_eq!(out.matches("list.txt").count(), 1, "{out}");
        assert!(out.contains("#2  [cos 0.52]"), "{out}");
        assert!(out.contains("#3  [cos 0.50]"), "{out}");
        assert!(out.contains("b.md"), "{out}");
        // The cosine-only format (reranker down) also yields a path.
        assert_eq!(
            rag_header_path("#1  [cos 0.50]  c.md  (C)"),
            Some("c.md".to_string())
        );
        assert_eq!(
            rag_header_path("#1  [cos 0.50]  rerank: -1.0  d.md  (D)"),
            Some("d.md".to_string())
        );
        assert_eq!(
            rag_header_path("#1  [cos 0.50]  rerank: -1.0  e.txt"),
            Some("e.txt".to_string())
        );
    }

    #[test]
    fn rag_count_label_includes_the_number() {
        assert_eq!(rag_count_label(1), " — 1 файл");
        assert_eq!(rag_count_label(2), " — 2 файла");
        assert_eq!(rag_count_label(5), " — 5 файлов");
        assert_eq!(rag_count_label(0), "");
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
        fs::create_dir_all(root.join(".zk/templates")).expect("template dir");
        fs::write(
            root.join(".zk/templates/note.md"),
            "---\ncreated: \"2000-01-01T00:00:00+00:00\"\ntitle: \"{{title}}\"\ndate: 2000-01-01\nuuid: 200001010000\ntags: []\ntype:\n---\n\n# {{title}}\n",
        )
        .expect("template");
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

        let created = execute(&Action::New {
            title: "Спор о депрессии".to_string(),
            body: "quick thought".to_string(),
        });
        assert!(created.contains("spor-o-depressii.md"), "{created}");
        let note = fs::read_to_string(root.join("spor-o-depressii.md")).expect("created note");
        assert!(note.contains("title: \"Спор о депрессии\""), "{note}");
        assert!(note.contains("# Спор о депрессии"), "{note}");
        assert!(note.contains("quick thought"), "{note}");
        assert!(!note.contains("2000-01-01"), "{note}");

        let duplicate = execute(&Action::New {
            title: "Спор о депрессии".to_string(),
            body: String::new(),
        });
        assert!(duplicate.contains("spor-o-depressii-2.md"), "{duplicate}");

        let shown = execute(&Action::Show("spor-o-depressii.md".to_string()));
        assert!(shown.contains("quick thought"), "{shown}");

        fs::write(root.join("long.md"), "x".repeat(9_000)).expect("long note");
        let read = call_tool("notes_read", r#"{"path":"long.md"}"#, false);
        assert!(
            read.contains("заметка обрезана"),
            "{}",
            &read[..read.len().min(200)]
        );
        assert!(
            read.contains("из 9000 символов"),
            "{}",
            &read[..read.len().min(200)]
        );
        assert!(read.len() <= MAX_TOOL_RESULT, "{}", read.len());

        std::env::remove_var("PILL_BOT_NOTES_DIR");
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn slugify_transliterates_and_falls_back() {
        assert_eq!(slugify("Спор о депрессии"), "spor-o-depressii");
        assert_eq!(slugify("SSH через прокси"), "ssh-cherez-proksi");
        assert_eq!(slugify("!!!"), "note");
        assert!(slugify(&"word ".repeat(30)).len() <= 60);
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
