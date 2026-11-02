//! Telegram chat access for the agent and the user (grammers user session).
//!
//! Rust replacement for `packages/tgchat/tg.py` (Telethon). Credentials come
//! from gopass (`api/telegram-telethon-id` / `api/telegram-telethon-hash`) or
//! from TELEGRAM_API_ID / TELEGRAM_API_HASH; the authorized session lives in
//! ~/.local/state/telegram-chat/session.sqlite. Telegram is reached through the
//! local sing-box socks proxy by default; override with TELEGRAM_PROXY, disable
//! with TELEGRAM_PROXY=off.
//!
//! The Telethon session file cannot be reused by another library: the first
//! run needs `tgchat-rs login` (phone code, plus the 2FA password if enabled).

use std::error::Error;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command as StdCommand, ExitCode};
use std::sync::Arc;

use clap::{Parser, Subcommand};
use grammers_client::message::InputMessage;
use grammers_client::peer::Peer;
use grammers_client::sender::{ConnectionParams, SenderPool};
use grammers_client::session::storages::SqliteSession;
use grammers_client::{Client, SignInError};
use serde_json::{json, Value};

type BoxError = Box<dyn Error + Send + Sync>;

const DEFAULT_PROXY: &str = "socks5://127.0.0.1:10808";

fn state_dir() -> PathBuf {
    let raw = std::env::var("TGCHAT_STATE")
        .unwrap_or_else(|_| "~/.local/state/telegram-chat".to_string());
    expand_home(&raw)
}

fn expand_home(path: &str) -> PathBuf {
    if let Some(rest) = path.strip_prefix("~/") {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
        Path::new(&home).join(rest)
    } else {
        PathBuf::from(path)
    }
}

fn fail(message: &str) -> ! {
    eprintln!("error: {message}");
    std::process::exit(1);
}

fn secret(name: &str) -> String {
    let env_name = match name {
        "api/telegram-telethon-id" => "TELEGRAM_API_ID",
        "api/telegram-telethon-hash" => "TELEGRAM_API_HASH",
        _ => "",
    };
    if !env_name.is_empty() {
        if let Ok(value) = std::env::var(env_name) {
            if !value.trim().is_empty() {
                return value.trim().to_string();
            }
        }
    }
    if let Ok(output) = StdCommand::new("gopass")
        .args(["show", "-o", name])
        .output()
    {
        if output.status.success() {
            let value = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !value.is_empty() {
                return value;
            }
        }
    }
    let store =
        std::env::var("PASSWORD_STORE_DIR").unwrap_or_else(|_| "~/.local/share/pass".to_string());
    let blob = expand_home(&store).join(format!("{name}.gpg"));
    if blob.exists() {
        if let Ok(output) = StdCommand::new("gpg")
            .args(["--batch", "--quiet", "--decrypt"])
            .arg(&blob)
            .output()
        {
            if output.status.success() {
                let value = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if !value.is_empty() {
                    return value;
                }
            }
        }
    }
    fail(&format!(
        "cannot read {name} (gopass/gpg and ${env_name} failed)"
    ));
}

fn proxy_url() -> Option<String> {
    let raw = std::env::var("TELEGRAM_PROXY").unwrap_or_else(|_| DEFAULT_PROXY.to_string());
    let raw = raw.trim().to_string();
    if raw.is_empty() || raw.eq_ignore_ascii_case("off") || raw.eq_ignore_ascii_case("none") {
        return None;
    }
    let with_scheme = if raw.contains("://") {
        raw
    } else {
        format!("socks5://{raw}")
    };
    if !with_scheme.starts_with("socks5://") {
        fail(&format!(
            "unsupported proxy scheme: {} (grammers speaks socks5)",
            with_scheme.split("://").next().unwrap_or("?")
        ));
    }
    Some(with_scheme)
}

async fn connect() -> Result<Client, BoxError> {
    let api_id: i32 = secret("api/telegram-telethon-id")
        .parse()
        .map_err(|_| "TELEGRAM_API_ID is not a number")?;
    let state = state_dir();
    std::fs::create_dir_all(&state)?;
    let session = Arc::new(SqliteSession::open(state.join("session.sqlite")).await?);

    let mut params = ConnectionParams::default();
    params.proxy_url = proxy_url();
    let SenderPool { runner, handle, .. } =
        SenderPool::with_configuration(Arc::clone(&session), api_id, params);
    let client = Client::new(handle);
    tokio::spawn(async move {
        runner.run().await;
    });
    Ok(client)
}

fn prompt(message: &str) -> String {
    print!("{message}");
    let _ = std::io::stdout().flush();
    let mut line = String::new();
    if std::io::stdin().read_line(&mut line).is_err() {
        fail("cannot read the answer from stdin");
    }
    line.trim().to_string()
}

fn stamp(moment: jiff::Timestamp) -> String {
    moment
        .to_zoned(jiff::tz::TimeZone::system())
        .strftime("%Y-%m-%d %H:%M")
        .to_string()
}

fn one_line(text: &str) -> String {
    let flat = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if flat.chars().count() <= 300 {
        flat
    } else {
        let mut short: String = flat.chars().take(299).collect();
        short.push('…');
        short
    }
}

fn name_of(user: &grammers_client::peer::User) -> String {
    let who = [user.first_name(), user.last_name()]
        .into_iter()
        .flatten()
        .collect::<Vec<_>>()
        .join(" ");
    let handle = user
        .username()
        .map(|name| format!(" (@{name})"))
        .unwrap_or_default();
    let id = user.id().bot_api_dialog_id_unchecked();
    format!(
        "{}{handle} id={id}",
        if who.is_empty() { "the account" } else { &who }
    )
}

fn sender_name(message: &grammers_client::message::Message) -> String {
    if let Some(peer) = message.sender() {
        if let Some(name) = peer.name() {
            return name.to_string();
        }
        if let Some(username) = peer.username() {
            return username.to_string();
        }
        return format!("{:?}", peer.id().bot_api_dialog_id_unchecked());
    }
    match message.sender_id() {
        Some(id) => id.bot_api_dialog_id_unchecked().to_string(),
        None => "?".to_string(),
    }
}

fn media_label(message: &grammers_client::message::Message) -> &'static str {
    use grammers_client::media::Media;
    match message.media() {
        Some(Media::Photo(_)) => "[photo]",
        Some(Media::Sticker(_)) => "[sticker]",
        Some(Media::Poll(_)) => "[poll]",
        Some(Media::Geo(_)) | Some(Media::GeoLive(_)) | Some(Media::Venue(_)) => "[geo]",
        Some(Media::Contact(_)) => "[contact]",
        Some(Media::Document(_)) => "[document]",
        Some(_) => "[media]",
        None => "[no text]",
    }
}

fn rendered(message: &grammers_client::message::Message) -> Value {
    json!({
        "id": message.id(),
        "date": stamp(message.date()),
        "sender": sender_name(message),
        "out": message.outgoing(),
        "text": if message.text().is_empty() { media_label(message) } else { message.text() },
    })
}

fn dialog_unread(dialog: &grammers_client::peer::Dialog) -> i32 {
    use grammers_client::tl::enums::Dialog as Raw;
    match &dialog.raw {
        Raw::Dialog(d) => d.unread_count,
        _ => 0,
    }
}

async fn resolve(client: &Client, name: &str) -> Result<Option<Peer>, BoxError> {
    if name.is_empty() {
        return Ok(None);
    }
    if let Ok(asked) = name.parse::<i64>() {
        let mut dialogs = client.iter_dialogs();
        while let Some(dialog) = dialogs.next().await? {
            if dialog.peer().id().bot_api_dialog_id_unchecked() == asked {
                return Ok(Some(dialog.peer().clone()));
            }
        }
    }
    let username = name
        .strip_prefix('@')
        .or_else(|| name.strip_prefix("https://t.me/"))
        .or_else(|| name.strip_prefix("t.me/"))
        .unwrap_or(name);
    if username != name || !username.is_empty() && !username.contains(' ') {
        if let Ok(Some(peer)) = client.resolve_username(username).await {
            return Ok(Some(peer));
        }
    }
    let needle = name.to_lowercase();
    let mut dialogs = client.iter_dialogs();
    let mut matches = Vec::new();
    while let Some(dialog) = dialogs.next().await? {
        let title = dialog.peer().name().unwrap_or_default().to_lowercase();
        if title.contains(&needle) {
            matches.push(dialog.peer().clone());
        }
    }
    match matches.len() {
        0 => Ok(None),
        1 => Ok(matches.pop()),
        _ => {
            let titles = matches
                .iter()
                .map(|peer| peer.name().unwrap_or("?").to_string())
                .collect::<Vec<_>>()
                .join(", ");
            Err(format!("{name:?} is ambiguous: {titles}").into())
        }
    }
}

async fn peer_ref(peer: &Peer) -> Result<grammers_session::types::PeerRef, BoxError> {
    match peer.to_ref().await? {
        Some(reference) => Ok(reference),
        None => Err("the peer is not in the session cache; open it once in Telegram".into()),
    }
}

async fn require_login(client: &Client) -> Result<(), BoxError> {
    if !client.is_authorized().await? {
        return Err("session not authorized — run `tgchat-rs login`".into());
    }
    Ok(())
}

async fn cmd_login(
    client: &Client,
    phone: Option<String>,
    code: Option<String>,
    password: Option<String>,
) -> Result<(), BoxError> {
    if client.is_authorized().await? {
        let me = client.get_me().await?;
        println!("already authorized as {}", name_of(&me));
        return Ok(());
    }
    let phone = phone.unwrap_or_else(|| prompt("phone (international format): "));
    let token = client
        .request_login_code(&phone, &secret("api/telegram-telethon-hash"))
        .await?;
    let code = code.unwrap_or_else(|| prompt("code from Telegram: "));
    match client.sign_in(&token, &code).await {
        Ok(me) => println!("authorized as {}", name_of(&me)),
        Err(SignInError::PasswordRequired(password_token)) => {
            let hint = password_token.hint().unwrap_or("None");
            let password = password
                .or_else(|| std::env::var("TELEGRAM_2FA").ok())
                .unwrap_or_else(|| prompt(&format!("2FA password (hint {hint}): ")));
            let me = client.check_password(password_token, &password).await?;
            println!("authorized as {}", name_of(&me));
        }
        Err(error) => return Err(format!("sign-in failed: {error}").into()),
    }
    Ok(())
}

async fn cmd_whoami(client: &Client, json_out: bool) -> Result<(), BoxError> {
    require_login(client).await?;
    let me = client.get_me().await?;
    if json_out {
        println!(
            "{}",
            serde_json::to_string_pretty(&json!({
                "id": me.id().bot_api_dialog_id_unchecked(),
                "first_name": me.first_name(),
                "last_name": me.last_name(),
                "username": me.username(),
                "phone": me.phone(),
            }))?
        );
    } else {
        println!(
            "{} {} (@{}) id={}",
            me.first_name().unwrap_or(""),
            me.last_name().unwrap_or(""),
            me.username().unwrap_or(""),
            me.id().bot_api_dialog_id_unchecked()
        );
    }
    Ok(())
}

async fn cmd_dialogs(client: &Client, limit: usize, json_out: bool) -> Result<(), BoxError> {
    require_login(client).await?;
    let mut dialogs = client.iter_dialogs();
    let mut rows: Vec<Value> = Vec::new();
    while let Some(dialog) = dialogs.next().await? {
        if rows.len() >= limit {
            break;
        }
        let when = dialog
            .last_message
            .as_ref()
            .map(|message| stamp(message.date()))
            .unwrap_or_else(|| "?".to_string());
        let last = dialog
            .last_message
            .as_ref()
            .map(|message| one_line(message.text()))
            .unwrap_or_default();
        rows.push(json!({
            "id": dialog.peer().id().bot_api_dialog_id_unchecked(),
            "title": dialog.peer().name(),
            "unread": dialog_unread(&dialog),
            "last": last,
            "when": when,
        }));
    }
    if json_out {
        println!("{}", serde_json::to_string_pretty(&rows)?);
        return Ok(());
    }
    for row in &rows {
        let unread = row["unread"].as_i64().unwrap_or(0);
        let unread = if unread > 0 {
            format!(" ({unread} unread)")
        } else {
            String::new()
        };
        println!(
            "{:>14}  {}  {}{}",
            row["id"].as_i64().unwrap_or(0),
            row["when"].as_str().unwrap_or("?"),
            row["title"].as_str().unwrap_or(""),
            unread
        );
        let last = row["last"].as_str().unwrap_or("");
        if !last.is_empty() {
            println!("{:>14}  · {last}", "");
        }
    }
    Ok(())
}

async fn tail_rows(client: &Client, chat: &str, number: usize) -> Result<Vec<Value>, BoxError> {
    let peer = resolve(client, chat)
        .await?
        .ok_or_else(|| format!("no dialog matches {chat:?}"))?;
    let reference = peer_ref(&peer).await?;
    let mut messages = client.iter_messages(reference).limit(number);
    let mut rows = Vec::new();
    while let Some(message) = messages.next().await? {
        rows.push(rendered(&message));
    }
    rows.reverse();
    Ok(rows)
}

async fn print_rows(rows: &[Value], json_out: bool) {
    if json_out {
        println!("{}", serde_json::to_string_pretty(rows).unwrap_or_default());
        return;
    }
    for row in rows {
        let who = if row["out"].as_bool().unwrap_or(false) {
            "me".to_string()
        } else {
            row["sender"].as_str().unwrap_or("?").to_string()
        };
        println!(
            "[{}] {who}: {}",
            row["date"].as_str().unwrap_or("?"),
            row["text"].as_str().unwrap_or("")
        );
    }
}

async fn cmd_tail(
    client: &Client,
    chat: Option<String>,
    number: usize,
    json_out: bool,
) -> Result<(), BoxError> {
    require_login(client).await?;
    let chat = chat.ok_or("tail needs a chat (see `dialogs`)")?;
    let rows = tail_rows(client, &chat, number).await?;
    print_rows(&rows, json_out).await;
    Ok(())
}

async fn cmd_search(
    client: &Client,
    query: String,
    chat: Option<String>,
    number: usize,
    json_out: bool,
) -> Result<(), BoxError> {
    require_login(client).await?;
    let mut rows = Vec::new();
    match chat {
        Some(chat) => {
            let peer = resolve(client, &chat)
                .await?
                .ok_or_else(|| format!("no dialog matches {chat:?}"))?;
            let reference = peer_ref(&peer).await?;
            let mut messages = client
                .search_messages(reference)
                .query(&query)
                .limit(number);
            while let Some(message) = messages.next().await? {
                rows.push(rendered(&message));
            }
        }
        None => {
            let mut messages = client.search_all_messages().query(&query).limit(number);
            while let Some(message) = messages.next().await? {
                rows.push(rendered(&message));
            }
        }
    }
    print_rows(&rows, json_out).await;
    Ok(())
}

async fn cmd_send(
    client: &Client,
    chat: String,
    text: Vec<String>,
    file: Option<String>,
    reply_to: Option<i32>,
) -> Result<(), BoxError> {
    require_login(client).await?;
    let peer = resolve(client, &chat)
        .await?
        .ok_or_else(|| format!("no dialog matches {chat:?}"))?;
    let reference = peer_ref(&peer).await?;
    let text = text.join(" ");
    if text.is_empty() && file.is_none() {
        return Err("nothing to send".into());
    }
    let mut message = InputMessage::new().text(&text);
    if let Some(reply_to) = reply_to {
        message = message.reply_to(Some(reply_to));
    }
    if let Some(path) = file {
        let uploaded = client.upload_file(&path).await?;
        message = message.document(uploaded);
    }
    let sent = client.send_message(reference, message).await?;
    println!("sent id={} to {chat}", sent.id());
    Ok(())
}

async fn cmd_export(
    client: &Client,
    chat: Option<String>,
    out: String,
    dialogs_limit: usize,
    per_chat: usize,
) -> Result<(), BoxError> {
    require_login(client).await?;
    let out = expand_home(&out);
    if let Some(parent) = out.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let peers: Vec<Peer> = match chat {
        Some(chat) => vec![resolve(client, &chat)
            .await?
            .ok_or_else(|| format!("no chat matches {chat:?}"))?],
        None => {
            let mut dialogs = client.iter_dialogs();
            let mut peers = Vec::new();
            while let Some(dialog) = dialogs.next().await? {
                if dialogs_limit > 0 && peers.len() >= dialogs_limit {
                    break;
                }
                peers.push(dialog.peer().clone());
            }
            peers
        }
    };
    let total_peers = peers.len();
    let mut written = 0usize;
    let mut failed = 0usize;
    let mut file = std::fs::File::create(&out)?;
    for peer in &peers {
        let title = peer
            .name()
            .or_else(|| peer.username())
            .unwrap_or("?")
            .to_string();
        let reference = match peer_ref(peer).await {
            Ok(reference) => reference,
            Err(error) => {
                failed += 1;
                eprintln!("skip {title}: {error}");
                continue;
            }
        };
        let mut messages = client.iter_messages(reference);
        if per_chat > 0 {
            messages = messages.limit(per_chat);
        }
        loop {
            match messages.next().await {
                Ok(Some(message)) => {
                    let mut row = rendered(&message);
                    row["chat"] = json!(title);
                    row["chat_id"] = json!(peer.id().bot_api_dialog_id_unchecked());
                    writeln!(file, "{}", serde_json::to_string(&row)?)?;
                    written += 1;
                }
                Ok(None) => break,
                Err(error) => {
                    failed += 1;
                    eprintln!("skip {title}: {error}");
                    break;
                }
            }
        }
    }
    println!(
        "wrote {written} messages from {} chats to {}",
        total_peers - failed,
        out.display()
    );
    Ok(())
}

#[derive(Parser)]
#[command(name = "tgchat-rs", about = "Telegram chat access via grammers")]
struct Cli {
    #[command(subcommand)]
    command: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// authorize the session (phone code, 2FA if enabled)
    Login {
        #[arg(long)]
        phone: Option<String>,
        #[arg(long)]
        code: Option<String>,
        #[arg(long)]
        password: Option<String>,
    },
    /// show the authorized account
    Whoami {
        #[arg(long)]
        json: bool,
    },
    /// list chats by recency
    Dialogs {
        #[arg(long, default_value_t = 20)]
        limit: usize,
        #[arg(long)]
        json: bool,
    },
    /// last messages of a chat
    Tail {
        chat: Option<String>,
        #[arg(short = 'n', long = "number", default_value_t = 20)]
        number: usize,
        #[arg(long)]
        json: bool,
    },
    /// search messages
    Search {
        query: String,
        #[arg(long)]
        chat: Option<String>,
        #[arg(short = 'n', long = "number", default_value_t = 20)]
        number: usize,
        #[arg(long)]
        json: bool,
    },
    /// write messages to a JSONL file
    Export {
        #[arg(long)]
        chat: Option<String>,
        #[arg(long, default_value = "~/telegram-export.jsonl")]
        out: String,
        #[arg(long, default_value_t = 0)]
        dialogs: usize,
        #[arg(long = "per-chat", default_value_t = 0)]
        per_chat: usize,
    },
    /// send a message
    Send {
        chat: String,
        #[arg(trailing_var_arg = true)]
        text: Vec<String>,
        #[arg(long)]
        file: Option<String>,
        #[arg(long = "reply-to")]
        reply_to: Option<i32>,
    },
}

#[tokio::main]
async fn main() -> ExitCode {
    let cli = Cli::parse();
    let client = match connect().await {
        Ok(client) => client,
        Err(error) => {
            eprintln!("error: {error}");
            return ExitCode::FAILURE;
        }
    };
    let result = match &cli.command {
        Cmd::Login {
            phone,
            code,
            password,
        } => cmd_login(&client, phone.clone(), code.clone(), password.clone()).await,
        Cmd::Whoami { json } => cmd_whoami(&client, *json).await,
        Cmd::Dialogs { limit, json } => cmd_dialogs(&client, *limit, *json).await,
        Cmd::Tail { chat, number, json } => cmd_tail(&client, chat.clone(), *number, *json).await,
        Cmd::Search {
            query,
            chat,
            number,
            json,
        } => cmd_search(&client, query.clone(), chat.clone(), *number, *json).await,
        Cmd::Export {
            chat,
            out,
            dialogs,
            per_chat,
        } => cmd_export(&client, chat.clone(), out.clone(), *dialogs, *per_chat).await,
        Cmd::Send {
            chat,
            text,
            file,
            reply_to,
        } => cmd_send(&client, chat.clone(), text.clone(), file.clone(), *reply_to).await,
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("error: {error}");
            ExitCode::FAILURE
        }
    }
}
