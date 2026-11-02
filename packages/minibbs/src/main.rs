//! minibbs — a tiny BBS-style message board.
//!
//! Rust port of `minibbs.py`. Boards hold threads, threads hold posts. The web
//! UI is read-only on purpose: bots write through the JSON API, humans read
//! (HTML or `?fmt=txt` for a plain-text BBS view). Storage is a single SQLite
//! file, so the data written by the Python version keeps working unchanged.
//!
//! Configuration comes from the environment:
//!   MINIBBS_DB         path to the SQLite file
//!   MINIBBS_TOKEN_FILE file holding the bearer token required for posting
//!   MINIBBS_BIND       listen address
//!   MINIBBS_PORT       listen port
//!   MINIBBS_TITLE      title shown in the web UI
//!
//! Posting:
//!   curl -sS -X POST http://<host>:<port>/api/post \
//!     -H "Authorization: Bearer $(cat <token-file>)" \
//!     -H 'Content-Type: application/json' \
//!     -d '{"board":"alerts","author":"crashloop","subject":"MPD restarted","body":"…"}'
//!   Appending to an existing thread: add `"thread": <id>` and drop `subject`.
//!
//! Reading:
//!   GET /                      board list (HTML; ?fmt=txt for text)
//!   GET /b/<slug>              threads in a board
//!   GET /t/<id>                one thread
//!   GET /api/boards            JSON board list
//!   GET /api/board/<slug>      JSON threads (newest activity first)
//!   GET /api/thread/<id>       JSON posts
//!   GET /healthz               liveness

use std::collections::BTreeMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::Arc;

const MAX_BODY: usize = 8192;
const MAX_SUBJECT: usize = 200;
const MAX_AUTHOR: usize = 64;

const SCHEMA: &str = "\
CREATE TABLE IF NOT EXISTS boards (
    id INTEGER PRIMARY KEY,
    slug TEXT UNIQUE NOT NULL,
    title TEXT NOT NULL,
    created TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS threads (
    id INTEGER PRIMARY KEY,
    board_id INTEGER NOT NULL REFERENCES boards(id),
    subject TEXT NOT NULL,
    created TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS posts (
    id INTEGER PRIMARY KEY,
    thread_id INTEGER NOT NULL REFERENCES threads(id),
    author TEXT NOT NULL,
    body TEXT NOT NULL,
    created TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS posts_thread ON posts(thread_id, id);
";

const PAGE: &str = "<!doctype html>
<html lang=\"en\"><head><meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
<title>{title}</title>
<style>
 body { background:#101014; color:#c8c8d0; font:14px/1.5 ui-monospace,monospace; margin:0; padding:24px; }
 a { color:#7fdbca; text-decoration:none; } a:hover { text-decoration:underline; }
 h1 { font-size:18px; color:#e8e8f0; } h2 { font-size:15px; margin:18px 0 6px; }
 table { border-collapse:collapse; width:100%; } td, th { text-align:left; padding:2px 12px 2px 0; vertical-align:top; }
 .dim { color:#6a6a78; } .post { border-left:2px solid #2a2a34; margin:12px 0; padding:2px 0 2px 12px; }
 pre { white-space:pre-wrap; font:inherit; margin:4px 0; }
</style></head><body>
<h1>{title}</h1>
<p class=\"dim\">{crumbs}</p>
{content}
<p class=\"dim\">read-only board &middot; bots post via <code>POST /api/post</code></p>
</body></html>";

/// Runtime configuration, read once at startup.
pub struct Config {
    pub db: String,
    pub token_file: String,
    pub bind: String,
    pub port: u16,
    pub title: String,
}

impl Config {
    fn from_env() -> Config {
        let get = |name: &str, fallback: &str| match std::env::var(name) {
            Ok(value) => value,
            Err(_) => fallback.to_string(),
        };
        Config {
            db: get("MINIBBS_DB", "/var/lib/minibbs/bbs.sqlite"),
            token_file: get("MINIBBS_TOKEN_FILE", ""),
            bind: get("MINIBBS_BIND", "127.0.0.1"),
            port: get("MINIBBS_PORT", "8091").trim().parse().unwrap_or(8091),
            title: get("MINIBBS_TITLE", "minibbs"),
        }
    }
}

// -- SQLite ------------------------------------------------------------

#[link(name = "sqlite3")]
extern "C" {
    fn sqlite3_open(filename: *const u8, db: *mut *mut SqliteHandle) -> i32;
    fn sqlite3_close(db: *mut SqliteHandle) -> i32;
    fn sqlite3_errmsg(db: *mut SqliteHandle) -> *const u8;
    fn sqlite3_exec(
        db: *mut SqliteHandle,
        sql: *const u8,
        callback: usize,
        arg: usize,
        errmsg: *mut *mut u8,
    ) -> i32;
    fn sqlite3_prepare_v2(
        db: *mut SqliteHandle,
        sql: *const u8,
        length: i32,
        stmt: *mut *mut SqliteStmt,
        tail: *mut *const u8,
    ) -> i32;
    fn sqlite3_step(stmt: *mut SqliteStmt) -> i32;
    fn sqlite3_finalize(stmt: *mut SqliteStmt) -> i32;
    fn sqlite3_bind_text(
        stmt: *mut SqliteStmt,
        index: i32,
        value: *const u8,
        length: i32,
        destructor: isize,
    ) -> i32;
    fn sqlite3_bind_int64(stmt: *mut SqliteStmt, index: i32, value: i64) -> i32;
    fn sqlite3_bind_null(stmt: *mut SqliteStmt, index: i32) -> i32;
    fn sqlite3_column_count(stmt: *mut SqliteStmt) -> i32;
    fn sqlite3_column_name(stmt: *mut SqliteStmt, column: i32) -> *const u8;
    fn sqlite3_column_type(stmt: *mut SqliteStmt, column: i32) -> i32;
    fn sqlite3_column_int64(stmt: *mut SqliteStmt, column: i32) -> i64;
    fn sqlite3_column_text(stmt: *mut SqliteStmt, column: i32) -> *const u8;
    fn sqlite3_last_insert_rowid(db: *mut SqliteHandle) -> i64;
    fn sqlite3_busy_timeout(db: *mut SqliteHandle, milliseconds: i32) -> i32;
}

#[repr(C)]
struct SqliteHandle {
    _private: [u8; 0],
}

#[repr(C)]
struct SqliteStmt {
    _private: [u8; 0],
}

const SQLITE_OK: i32 = 0;
const SQLITE_ROW: i32 = 100;
const SQLITE_DONE: i32 = 101;
const SQLITE_NULL: i32 = 5;
const SQLITE_TRANSIENT: isize = -1;

/// One column value, in the shapes the board stores.
#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Null,
    Integer(i64),
    Text(String),
}

impl Value {
    fn as_text(&self) -> String {
        match self {
            Value::Null => String::new(),
            Value::Integer(number) => number.to_string(),
            Value::Text(text) => text.clone(),
        }
    }

    fn is_null(&self) -> bool {
        matches!(self, Value::Null)
    }
}

/// A result row: column name -> value, in select order.
pub type Row = Vec<(String, Value)>;

fn row_get<'a>(row: &'a Row, column: &str) -> Option<&'a Value> {
    row.iter()
        .find(|(name, _)| name == column)
        .map(|(_, value)| value)
}

fn row_text(row: &Row, column: &str) -> String {
    row_get(row, column).map(Value::as_text).unwrap_or_default()
}

pub struct Db {
    handle: *mut SqliteHandle,
}

impl Db {
    pub fn open(path: &str) -> Result<Db, String> {
        let mut handle: *mut SqliteHandle = std::ptr::null_mut();
        let status = unsafe {
            let mut name = path.as_bytes().to_vec();
            name.push(0);
            sqlite3_open(name.as_ptr(), &mut handle)
        };
        if status != SQLITE_OK {
            return Err(format!("cannot open {path}"));
        }
        let db = Db { handle };
        db.exec("PRAGMA journal_mode=WAL")?;
        db.exec("PRAGMA foreign_keys=ON")?;
        unsafe {
            sqlite3_busy_timeout(db.handle, 10_000);
        }
        Ok(db)
    }

    fn c_string(raw: *const u8) -> String {
        if raw.is_null() {
            return String::new();
        }
        unsafe {
            let mut length = 0usize;
            while *raw.add(length) != 0 {
                length += 1;
            }
            String::from_utf8_lossy(std::slice::from_raw_parts(raw, length)).to_string()
        }
    }

    fn error(&self) -> String {
        let message = Db::c_string(unsafe { sqlite3_errmsg(self.handle) });
        if message.is_empty() {
            "sqlite error".to_string()
        } else {
            message
        }
    }

    pub fn exec(&self, sql: &str) -> Result<(), String> {
        let status = unsafe {
            let mut text = sql.as_bytes().to_vec();
            text.push(0);
            sqlite3_exec(self.handle, text.as_ptr(), 0, 0, std::ptr::null_mut())
        };
        if status == SQLITE_OK {
            Ok(())
        } else {
            Err(self.error())
        }
    }

    /// Run a statement and collect its rows.
    pub fn query(&self, sql: &str, params: &[Value]) -> Result<Vec<Row>, String> {
        let statement = self.prepare(sql, params)?;
        let mut rows = Vec::new();
        loop {
            let status = unsafe { sqlite3_step(statement) };
            if status == SQLITE_ROW {
                let count = unsafe { sqlite3_column_count(statement) };
                let mut row: Row = Vec::new();
                for column in 0..count {
                    let name = Db::c_string(unsafe { sqlite3_column_name(statement, column) });
                    let kind = unsafe { sqlite3_column_type(statement, column) };
                    let value = if kind == SQLITE_NULL {
                        Value::Null
                    } else if kind == 2 || kind == 1 {
                        Value::Integer(unsafe { sqlite3_column_int64(statement, column) })
                    } else {
                        Value::Text(Db::c_string(unsafe {
                            sqlite3_column_text(statement, column)
                        }))
                    };
                    row.push((name, value));
                }
                rows.push(row);
            } else if status == SQLITE_DONE {
                break;
            } else {
                unsafe { sqlite3_finalize(statement) };
                return Err(self.error());
            }
        }
        unsafe { sqlite3_finalize(statement) };
        Ok(rows)
    }

    /// Run an insert/update and return the new rowid.
    pub fn execute(&self, sql: &str, params: &[Value]) -> Result<i64, String> {
        let statement = self.prepare(sql, params)?;
        let status = unsafe { sqlite3_step(statement) };
        let result = if status == SQLITE_DONE || status == SQLITE_ROW {
            Ok(unsafe { sqlite3_last_insert_rowid(self.handle) })
        } else {
            Err(self.error())
        };
        unsafe { sqlite3_finalize(statement) };
        result
    }

    fn prepare(&self, sql: &str, params: &[Value]) -> Result<*mut SqliteStmt, String> {
        let mut statement: *mut SqliteStmt = std::ptr::null_mut();
        let status = unsafe {
            let mut text = sql.as_bytes().to_vec();
            text.push(0);
            sqlite3_prepare_v2(
                self.handle,
                text.as_ptr(),
                -1,
                &mut statement,
                std::ptr::null_mut(),
            )
        };
        if status != SQLITE_OK || statement.is_null() {
            return Err(self.error());
        }
        for (index, value) in params.iter().enumerate() {
            let slot = index as i32 + 1;
            let status = unsafe {
                match value {
                    Value::Null => sqlite3_bind_null(statement, slot),
                    Value::Integer(number) => sqlite3_bind_int64(statement, slot, *number),
                    Value::Text(text) => sqlite3_bind_text(
                        statement,
                        slot,
                        text.as_ptr(),
                        text.len() as i32,
                        SQLITE_TRANSIENT,
                    ),
                }
            };
            if status != SQLITE_OK {
                unsafe { sqlite3_finalize(statement) };
                return Err(self.error());
            }
        }
        Ok(statement)
    }
}

impl Drop for Db {
    fn drop(&mut self) {
        unsafe { sqlite3_close(self.handle) };
    }
}

// -- time --------------------------------------------------------------

/// UTC timestamp without microseconds: `2026-11-02T06:00:00+00:00`.
pub fn now() -> String {
    let seconds = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|delta| delta.as_secs() as i64)
        .unwrap_or(0);
    iso8601_utc(seconds)
}

pub fn iso8601_utc(seconds: i64) -> String {
    let days = seconds.div_euclid(86_400);
    let remainder = seconds.rem_euclid(86_400);
    let (year, month, day) = civil_from_days(days);
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}+00:00",
        remainder / 3600,
        (remainder % 3600) / 60,
        remainder % 60
    )
}

/// Howard Hinnant's `civil_from_days`.
fn civil_from_days(days: i64) -> (i64, i64, i64) {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (if m <= 2 { y + 1 } else { y }, m, d)
}

// -- rendering ---------------------------------------------------------

pub fn esc(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for ch in value.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#x27;"),
            other => out.push(other),
        }
    }
    out
}

fn body_html(text: &str) -> String {
    text.split('\n').map(esc).collect::<Vec<_>>().join("<br>")
}

fn page(config: &Config, crumbs: &str, content: &str) -> String {
    PAGE.replace("{title}", &esc(&config.title))
        .replace("{crumbs}", crumbs)
        .replace("{content}", content)
}

fn render_boards(rows: &[Row]) -> String {
    if rows.is_empty() {
        return "<p>no boards yet</p>".to_string();
    }
    let mut out = vec![
        "<table><tr><th>board</th><th>threads</th><th>posts</th><th>last</th></tr>".to_string(),
    ];
    for row in rows {
        let slug = row_text(row, "slug");
        let last = row_get(row, "last").cloned().unwrap_or(Value::Null);
        out.push(format!(
            "<tr><td><a href='/b/{}'>{}</a></td><td>{}</td><td>{}</td><td class='dim'>{}</td></tr>",
            esc(&slug),
            esc(&slug),
            row_text(row, "threads"),
            row_text(row, "posts"),
            esc(&if last.is_null() {
                "-".to_string()
            } else {
                last.as_text()
            })
        ));
    }
    out.join("\n") + "</table>"
}

fn render_threads(slug: &str, rows: &[Row]) -> String {
    if rows.is_empty() {
        return format!("<p>board <b>{}</b> is empty</p>", esc(slug));
    }
    let mut out = vec![
        format!("<h2>{}</h2>", esc(slug)),
        "<table><tr><th>#</th><th>subject</th><th>posts</th><th>last</th></tr>".to_string(),
    ];
    for row in rows {
        let last = row_get(row, "last").cloned().unwrap_or(Value::Null);
        let author = row_get(row, "author").cloned().unwrap_or(Value::Null);
        out.push(format!(
            "<tr><td><a href='/t/{}'>{}</a></td><td>{}</td><td>{}</td><td class='dim'>{} {}</td></tr>",
            row_text(row, "id"),
            row_text(row, "id"),
            esc(&row_text(row, "subject")),
            row_text(row, "posts"),
            esc(&if last.is_null() { "-".to_string() } else { last.as_text() }),
            esc(&if author.is_null() { String::new() } else { author.as_text() })
        ));
    }
    out.join("\n") + "</table>"
}

fn render_posts(thread: &Row, posts: &[Row]) -> String {
    let mut out = vec![format!(
        "<h2>#{} {}</h2>",
        row_text(thread, "id"),
        esc(&row_text(thread, "subject"))
    )];
    for post in posts {
        out.push(format!(
            "<div class='post'><p class='dim'>#{} {} &middot; {}</p><pre>{}</pre></div>",
            row_text(post, "id"),
            esc(&row_text(post, "author")),
            esc(&row_text(post, "created")),
            body_html(&row_text(post, "body"))
        ));
    }
    out.join("\n")
}

/// Plain-text rendering for `?fmt=txt` and text-accepting clients.
fn as_text(kind: &str, rows: &[Row]) -> String {
    let mut lines = Vec::new();
    if kind == "boards" {
        for row in rows {
            let last = row_get(row, "last").cloned().unwrap_or(Value::Null);
            lines.push(format!(
                "{:<16} {} threads {} posts  {}",
                row_text(row, "slug"),
                row_text(row, "threads"),
                row_text(row, "posts"),
                if last.is_null() {
                    "-".to_string()
                } else {
                    last.as_text()
                }
            ));
        }
    } else {
        for row in rows {
            let last = row_get(row, "last").cloned().unwrap_or(Value::Null);
            lines.push(format!(
                "#{:<5} {}  ({} posts, last {})",
                row_text(row, "id"),
                row_text(row, "subject"),
                row_text(row, "posts"),
                if last.is_null() {
                    "-".to_string()
                } else {
                    last.as_text()
                }
            ));
        }
    }
    lines.join("\n") + "\n"
}

fn json_row(row: &Row) -> String {
    let mut parts = Vec::new();
    for (name, value) in row {
        let rendered = match value {
            Value::Null => "null".to_string(),
            Value::Integer(number) => number.to_string(),
            Value::Text(text) => format!("\"{}\"", json_escape(text)),
        };
        parts.push(format!("\"{}\": {rendered}", json_escape(name)));
    }
    format!("{{{}}}", parts.join(", "))
}

fn json_escape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for ch in text.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            ch if (ch as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", ch as u32)),
            ch => out.push(ch),
        }
    }
    out
}

fn json_rows(rows: &[Row]) -> String {
    format!(
        "[{}]",
        rows.iter().map(json_row).collect::<Vec<_>>().join(", ")
    )
}

// -- queries -----------------------------------------------------------

pub fn boards(db: &Db) -> Vec<Row> {
    db.query(
        "SELECT b.slug, b.title,
                (SELECT count(*) FROM threads t WHERE t.board_id = b.id) AS threads,
                (SELECT count(*) FROM posts p JOIN threads t ON t.id = p.thread_id
                  WHERE t.board_id = b.id) AS posts,
                (SELECT max(p.created) FROM posts p JOIN threads t ON t.id = p.thread_id
                  WHERE t.board_id = b.id) AS last
           FROM boards b
       ORDER BY b.slug",
        &[],
    )
    .unwrap_or_default()
}

pub fn threads_of(db: &Db, slug: &str, limit: i64) -> Vec<Row> {
    db.query(
        "SELECT t.id, t.subject, t.created,
                (SELECT count(*) FROM posts p WHERE p.thread_id = t.id) AS posts,
                (SELECT p.author FROM posts p WHERE p.thread_id = t.id ORDER BY p.id LIMIT 1) AS author,
                (SELECT max(p.created) FROM posts p WHERE p.thread_id = t.id) AS last
           FROM threads t JOIN boards b ON b.id = t.board_id
          WHERE b.slug = ?
       ORDER BY last DESC, t.id DESC
          LIMIT ?",
        &[Value::Text(slug.to_string()), Value::Integer(limit)],
    )
    .unwrap_or_default()
}

pub fn thread_with_posts(db: &Db, id: &str) -> (Option<Row>, Vec<Row>) {
    let thread = db
        .query(
            "SELECT t.id, t.subject, t.created, b.slug AS board
               FROM threads t JOIN boards b ON b.id = t.board_id
              WHERE t.id = ?",
            &[Value::Text(id.to_string())],
        )
        .unwrap_or_default()
        .into_iter()
        .next();
    let Some(thread) = thread else {
        return (None, Vec::new());
    };
    let posts = db
        .query(
            "SELECT id, author, body, created FROM posts WHERE thread_id = ? ORDER BY id",
            &[Value::Text(row_text(&thread, "id"))],
        )
        .unwrap_or_default();
    (Some(thread), posts)
}

// -- HTTP --------------------------------------------------------------

struct Request {
    method: String,
    path: String,
    query: Vec<(String, String)>,
    headers: BTreeMap<String, String>,
    body: Vec<u8>,
}

impl Request {
    fn header(&self, name: &str) -> &str {
        self.headers
            .get(&name.to_lowercase())
            .map(String::as_str)
            .unwrap_or("")
    }

    fn param(&self, name: &str) -> Option<&str> {
        self.query
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.as_str())
    }

    fn wants_text(&self) -> bool {
        self.param("fmt") == Some("txt") || self.header("accept").contains("text/plain")
    }
}

fn response(status: &str, content_type: &str, body: &[u8]) -> Vec<u8> {
    let mut out = format!(
        "HTTP/1.1 {status}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        body.len()
    )
    .into_bytes();
    out.extend_from_slice(body);
    out
}

fn handle(mut stream: TcpStream, db_path: Arc<String>, config: Arc<Config>) {
    let Ok(mut writer) = stream.try_clone() else {
        return;
    };
    let mut reader = BufReader::new(&mut stream);
    let mut request_line = String::new();
    if reader.read_line(&mut request_line).is_err() {
        return;
    }
    let mut words = request_line.split_whitespace();
    let method = words.next().unwrap_or("").to_string();
    let target = words.next().unwrap_or("/").to_string();
    let mut headers: BTreeMap<String, String> = BTreeMap::new();
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line).is_err() {
            return;
        }
        let line = line.trim_end();
        if line.is_empty() {
            break;
        }
        if let Some((name, value)) = line.split_once(':') {
            headers.insert(name.trim().to_lowercase(), value.trim().to_string());
        }
    }
    let length: usize = headers
        .get("content-length")
        .and_then(|value| value.trim().parse().ok())
        .unwrap_or(0);
    let mut body = vec![0u8; length];
    if length > 0 && reader.read_exact(&mut body).is_err() {
        return;
    }
    let (path, query) = split_target(&target);
    let request = Request {
        method,
        path,
        query,
        headers,
        body,
    };
    let payload = route(&request, &db_path, &config);
    let _ = writer.write_all(&payload);
    let _ = writer.flush();
}

fn split_target(target: &str) -> (String, Vec<(String, String)>) {
    match target.split_once('?') {
        Some((path, query)) => (normalise_path(path), parse_query(query)),
        None => (normalise_path(target), Vec::new()),
    }
}

fn normalise_path(path: &str) -> String {
    let trimmed = path.trim_end_matches('/');
    if trimmed.is_empty() {
        "/".to_string()
    } else {
        trimmed.to_string()
    }
}

pub fn parse_query(query: &str) -> Vec<(String, String)> {
    query
        .split('&')
        .filter(|pair| !pair.is_empty())
        .map(|pair| match pair.split_once('=') {
            Some((key, value)) => (percent_decode(key), percent_decode(value)),
            None => (percent_decode(pair), String::new()),
        })
        .collect()
}

pub fn percent_decode(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        match bytes[index] {
            b'+' => {
                out.push(b' ');
                index += 1;
            }
            b'%' if index + 2 < bytes.len() => {
                let hex = std::str::from_utf8(&bytes[index + 1..index + 3]).unwrap_or("");
                match u8::from_str_radix(hex, 16) {
                    Ok(value) => {
                        out.push(value);
                        index += 3;
                    }
                    Err(_) => {
                        out.push(b'%');
                        index += 1;
                    }
                }
            }
            byte => {
                out.push(byte);
                index += 1;
            }
        }
    }
    String::from_utf8_lossy(&out).to_string()
}

fn route(request: &Request, db_path: &str, config: &Config) -> Vec<u8> {
    let Ok(db) = Db::open(db_path) else {
        return response(
            "500 Internal Server Error",
            "application/json; charset=utf-8",
            b"{\"error\": \"database unavailable\"}",
        );
    };
    if request.method == "POST" {
        return post(&request, &db);
    }
    let path = request.path.as_str();
    let json = |code: &str, body: String| {
        response(code, "application/json; charset=utf-8", body.as_bytes())
    };
    if path == "/" || path == "/index.html" {
        let rows = boards(&db);
        if request.wants_text() {
            return response(
                "200 OK",
                "text/plain; charset=utf-8",
                as_text("boards", &rows).as_bytes(),
            );
        }
        return response(
            "200 OK",
            "text/html; charset=utf-8",
            page(config, "boards", &render_boards(&rows)).as_bytes(),
        );
    }
    if path == "/healthz" {
        return response("200 OK", "text/plain; charset=utf-8", b"ok\n");
    }
    if path == "/api/boards" {
        return json(
            "200 OK",
            format!("{{\"boards\": {}}}\n", json_rows(&boards(&db))),
        );
    }
    if let Some(slug) = path.strip_prefix("/b/") {
        let rows = threads_of(&db, slug, 200);
        if request.wants_text() {
            return response(
                "200 OK",
                "text/plain; charset=utf-8",
                as_text("threads", &rows).as_bytes(),
            );
        }
        let crumbs = format!("boards / <a href='/b/{}'>{}</a>", esc(slug), esc(slug));
        return response(
            "200 OK",
            "text/html; charset=utf-8",
            page(config, &crumbs, &render_threads(slug, &rows)).as_bytes(),
        );
    }
    if let Some(slug) = path.strip_prefix("/api/board/") {
        let limit = request
            .param("limit")
            .and_then(|value| value.trim().parse::<i64>().ok())
            .map(|value| value.min(500))
            .unwrap_or(100);
        let rows = threads_of(&db, slug, limit);
        return json(
            "200 OK",
            format!(
                "{{\"board\": \"{}\", \"threads\": {}}}\n",
                json_escape(slug),
                json_rows(&rows)
            ),
        );
    }
    let (is_api, id) = if let Some(id) = path.strip_prefix("/api/thread/") {
        (true, id)
    } else if let Some(id) = path.strip_prefix("/t/") {
        (false, id)
    } else {
        return json("404 Not Found", "{\"error\": \"not found\"}\n".to_string());
    };
    let (thread, posts) = thread_with_posts(&db, id);
    let Some(thread) = thread else {
        if is_api {
            return json(
                "404 Not Found",
                "{\"error\": \"no such thread\"}\n".to_string(),
            );
        }
        return response(
            "404 Not Found",
            "text/html; charset=utf-8",
            page(config, "boards", "<p>no such thread</p>").as_bytes(),
        );
    };
    if is_api {
        return json(
            "200 OK",
            format!(
                "{{\"thread\": {}, \"posts\": {}}}\n",
                json_row(&thread),
                json_rows(&posts)
            ),
        );
    }
    let board = row_text(&thread, "board");
    let crumbs = format!(
        "boards / <a href='/b/{}'>{}</a> / #{}",
        esc(&board),
        esc(&board),
        row_text(&thread, "id")
    );
    response(
        "200 OK",
        "text/html; charset=utf-8",
        page(config, &crumbs, &render_posts(&thread, &posts)).as_bytes(),
    )
}

fn post(request: &Request, db: &Db) -> Vec<u8> {
    let json = |code: &str, body: String| {
        response(code, "application/json; charset=utf-8", body.as_bytes())
    };
    let header = request.header("authorization").to_string();
    let token = if header.to_lowercase().starts_with("bearer ") {
        header[7..].to_string()
    } else {
        request.param("token").unwrap_or("").to_string()
    };
    if !token_ok(&token) {
        return json(
            "401 Unauthorized",
            "{\"error\": \"invalid or missing token\"}\n".to_string(),
        );
    }
    let length = request.body.len();
    if length > MAX_BODY * 2 {
        return json(
            "413 Payload Too Large",
            "{\"error\": \"payload too large\"}\n".to_string(),
        );
    }
    let raw = String::from_utf8_lossy(&request.body).to_string();
    let mut fields: Vec<(String, String)> = Vec::new();
    if request.header("content-type").contains("application/json") {
        let Some(value) = jsonok::parse(&raw) else {
            return json(
                "400 Bad Request",
                "{\"error\": \"body must be JSON or form-encoded\"}\n".to_string(),
            );
        };
        if let jsonok::Value::Object(entries) = value {
            for (key, value) in entries {
                fields.push((key, value.as_text()));
            }
        }
    } else {
        for (key, value) in parse_query(&raw) {
            fields.push((key, value));
        }
        for (key, value) in &request.query {
            if key != "token" {
                fields.push((key.clone(), value.clone()));
            }
        }
    }
    let field = |name: &str| {
        fields
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.clone())
            .unwrap_or_default()
    };
    let board = field("board").trim().to_lowercase();
    let author_raw = field("author");
    let author: String = if author_raw.is_empty() {
        "anon".to_string()
    } else {
        author_raw.trim().chars().take(MAX_AUTHOR).collect()
    };
    let subject_raw = field("subject");
    let mut subject: String = subject_raw.trim().chars().take(MAX_SUBJECT).collect();
    let body = field("body").trim().to_string();
    let thread_id = field("thread");

    if !slug_ok(&board) {
        return json(
            "400 Bad Request",
            "{\"error\": \"board must match [a-z0-9][a-z0-9_-]{0,31}\"}\n".to_string(),
        );
    }
    if body.is_empty() {
        return json(
            "400 Bad Request",
            "{\"error\": \"body is required\"}\n".to_string(),
        );
    }
    if body.len() > MAX_BODY {
        return json(
            "413 Payload Too Large",
            format!("{{\"error\": \"body limited to {MAX_BODY} bytes\"}}\n"),
        );
    }
    if subject.is_empty() {
        subject = body.lines().next().unwrap_or("").chars().take(60).collect();
    }
    let created = now();
    let _ = db.execute(
        "INSERT INTO boards(slug, title, created) VALUES(?, ?, ?) ON CONFLICT(slug) DO NOTHING",
        &[
            Value::Text(board.clone()),
            Value::Text(board.clone()),
            Value::Text(created.clone()),
        ],
    );
    let Ok(rows) = db.query(
        "SELECT id FROM boards WHERE slug = ?",
        &[Value::Text(board.clone())],
    ) else {
        return json(
            "500 Internal Server Error",
            "{\"error\": \"database error\"}\n".to_string(),
        );
    };
    let Some(board_row) = rows.first() else {
        return json(
            "500 Internal Server Error",
            "{\"error\": \"database error\"}\n".to_string(),
        );
    };
    let board_id = row_text(board_row, "id");
    let tid = if thread_id.is_empty() {
        match db.execute(
            "INSERT INTO threads(board_id, subject, created) VALUES(?, ?, ?)",
            &[
                Value::Text(board_id.clone()),
                Value::Text(subject.clone()),
                Value::Text(created.clone()),
            ],
        ) {
            Ok(id) => id.to_string(),
            Err(_) => {
                return json(
                    "500 Internal Server Error",
                    "{\"error\": \"database error\"}\n".to_string(),
                )
            }
        }
    } else {
        let Ok(existing) = db.query(
            "SELECT id FROM threads WHERE id = ? AND board_id = ?",
            &[
                Value::Text(thread_id.clone()),
                Value::Text(board_id.clone()),
            ],
        ) else {
            return json(
                "500 Internal Server Error",
                "{\"error\": \"database error\"}\n".to_string(),
            );
        };
        let Some(existing) = existing.first() else {
            return json(
                "404 Not Found",
                "{\"error\": \"no such thread in this board\"}\n".to_string(),
            );
        };
        row_text(existing, "id")
    };
    let pid = match db.execute(
        "INSERT INTO posts(thread_id, author, body, created) VALUES(?, ?, ?, ?)",
        &[
            Value::Text(tid.clone()),
            Value::Text(author),
            Value::Text(body),
            Value::Text(created),
        ],
    ) {
        Ok(id) => id,
        Err(_) => {
            return json(
                "500 Internal Server Error",
                "{\"error\": \"database error\"}\n".to_string(),
            )
        }
    };
    json(
        "201 Created",
        format!(
            "{{\"ok\": true, \"board\": \"{}\", \"thread\": {tid}, \"post\": {pid}, \"url\": \"/t/{tid}\"}}\n",
            json_escape(&board)
        ),
    )
}

fn slug_ok(board: &str) -> bool {
    let chars: Vec<char> = board.chars().collect();
    if chars.is_empty() || chars.len() > 32 {
        return false;
    }
    let first = chars[0];
    if !first.is_ascii_lowercase() && !first.is_ascii_digit() {
        return false;
    }
    chars
        .iter()
        .all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || *ch == '_' || *ch == '-')
}

/// Compare against the token file on every request, so rotation needs no restart.
fn token_ok(supplied: &str) -> bool {
    let token_file = std::env::var("MINIBBS_TOKEN_FILE").unwrap_or_default();
    if token_file.is_empty() || supplied.is_empty() {
        return false;
    }
    let Ok(expected) = std::fs::read_to_string(&token_file) else {
        return false;
    };
    let expected = expected.trim();
    !expected.is_empty() && constant_time_eq(expected.as_bytes(), supplied.as_bytes())
}

fn constant_time_eq(left: &[u8], right: &[u8]) -> bool {
    if left.len() != right.len() {
        return false;
    }
    let mut diff = 0u8;
    for (a, b) in left.iter().zip(right.iter()) {
        diff |= a ^ b;
    }
    diff == 0
}

fn main() -> std::process::ExitCode {
    let config = Config::from_env();
    if let Ok(db) = Db::open(&config.db) {
        if let Err(exc) = db.exec(SCHEMA) {
            eprintln!("minibbs: cannot create the schema: {exc}");
            return std::process::ExitCode::from(1);
        }
    } else {
        eprintln!("minibbs: cannot open {}", config.db);
        return std::process::ExitCode::from(1);
    }
    let address = format!("{}:{}", config.bind, config.port);
    let listener = match TcpListener::bind(&address) {
        Ok(listener) => listener,
        Err(exc) => {
            eprintln!("minibbs: cannot listen on {address}: {exc}");
            return std::process::ExitCode::from(1);
        }
    };
    println!(
        "minibbs listening on {}:{} db={}",
        config.bind, config.port, config.db
    );
    let _ = std::io::stdout().flush();
    let config = Arc::new(config);
    let db = Arc::new(config.db.clone());
    for stream in listener.incoming().flatten() {
        let config = Arc::clone(&config);
        let db = Arc::clone(&db);
        std::thread::spawn(move || handle(stream, db, config));
    }
    std::process::ExitCode::SUCCESS
}

/// JSON reader for the POST body (objects of strings, numbers and booleans).
mod jsonok {
    #[derive(Debug, Clone, PartialEq)]
    pub enum Value {
        Null,
        Bool(bool),
        Number(f64),
        Str(String),
        Array(Vec<Value>),
        Object(Vec<(String, Value)>),
    }

    impl Value {
        pub fn as_text(&self) -> String {
            match self {
                Value::Null => String::new(),
                Value::Bool(flag) => {
                    if *flag {
                        "True".to_string()
                    } else {
                        "False".to_string()
                    }
                }
                Value::Number(number) => {
                    if number.fract() == 0.0 && number.abs() < 1e15 {
                        format!("{}", *number as i64)
                    } else {
                        format!("{number}")
                    }
                }
                Value::Str(text) => text.clone(),
                Value::Array(items) => items
                    .iter()
                    .map(Value::as_text)
                    .collect::<Vec<_>>()
                    .join(" "),
                Value::Object(_) => String::new(),
            }
        }
    }

    pub fn parse(text: &str) -> Option<Value> {
        let chars: Vec<char> = text.chars().collect();
        let mut parser = Parser { chars, pos: 0 };
        let value = parser.value()?;
        parser.skip_ws();
        if parser.pos != parser.chars.len() {
            return None;
        }
        Some(value)
    }

    struct Parser {
        chars: Vec<char>,
        pos: usize,
    }

    impl Parser {
        fn peek(&self) -> Option<char> {
            self.chars.get(self.pos).copied()
        }

        fn skip_ws(&mut self) {
            while matches!(self.peek(), Some(ch) if ch.is_whitespace()) {
                self.pos += 1;
            }
        }

        fn eat(&mut self, ch: char) -> bool {
            if self.peek() == Some(ch) {
                self.pos += 1;
                true
            } else {
                false
            }
        }

        fn value(&mut self) -> Option<Value> {
            self.skip_ws();
            match self.peek()? {
                '{' => self.object(),
                '[' => self.array(),
                '"' => self.string().map(Value::Str),
                't' => self.literal("true", Value::Bool(true)),
                'f' => self.literal("false", Value::Bool(false)),
                'n' => self.literal("null", Value::Null),
                _ => self.number(),
            }
        }

        fn literal(&mut self, text: &str, value: Value) -> Option<Value> {
            for expected in text.chars() {
                if self.peek()? != expected {
                    return None;
                }
                self.pos += 1;
            }
            Some(value)
        }

        fn object(&mut self) -> Option<Value> {
            self.pos += 1;
            let mut entries = Vec::new();
            self.skip_ws();
            if self.eat('}') {
                return Some(Value::Object(entries));
            }
            loop {
                self.skip_ws();
                let key = self.string()?;
                self.skip_ws();
                if !self.eat(':') {
                    return None;
                }
                entries.push((key, self.value()?));
                self.skip_ws();
                if self.eat(',') {
                    continue;
                }
                if self.eat('}') {
                    return Some(Value::Object(entries));
                }
                return None;
            }
        }

        fn array(&mut self) -> Option<Value> {
            self.pos += 1;
            let mut items = Vec::new();
            self.skip_ws();
            if self.eat(']') {
                return Some(Value::Array(items));
            }
            loop {
                items.push(self.value()?);
                self.skip_ws();
                if self.eat(',') {
                    continue;
                }
                if self.eat(']') {
                    return Some(Value::Array(items));
                }
                return None;
            }
        }

        fn string(&mut self) -> Option<String> {
            if !self.eat('"') {
                return None;
            }
            let mut out = String::new();
            loop {
                let ch = self.peek()?;
                self.pos += 1;
                match ch {
                    '"' => return Some(out),
                    '\\' => {
                        let escaped = self.peek()?;
                        self.pos += 1;
                        match escaped {
                            '"' => out.push('"'),
                            '\\' => out.push('\\'),
                            '/' => out.push('/'),
                            'n' => out.push('\n'),
                            't' => out.push('\t'),
                            'r' => out.push('\r'),
                            'u' => {
                                let mut code = String::new();
                                for _ in 0..4 {
                                    code.push(self.peek()?);
                                    self.pos += 1;
                                }
                                let value = u32::from_str_radix(&code, 16).ok()?;
                                out.push(char::from_u32(value).unwrap_or('\u{fffd}'));
                            }
                            other => out.push(other),
                        }
                    }
                    other => out.push(other),
                }
            }
        }

        fn number(&mut self) -> Option<Value> {
            let start = self.pos;
            if matches!(self.peek(), Some('-')) {
                self.pos += 1;
            }
            while matches!(self.peek(), Some(ch) if ch.is_ascii_digit()) {
                self.pos += 1;
            }
            if matches!(self.peek(), Some('.')) {
                self.pos += 1;
                while matches!(self.peek(), Some(ch) if ch.is_ascii_digit()) {
                    self.pos += 1;
                }
            }
            if self.pos == start {
                return None;
            }
            let text: String = self.chars[start..self.pos].iter().collect();
            text.parse::<f64>().ok().map(Value::Number)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slugs_follow_the_documented_pattern() {
        assert!(slug_ok("alerts"));
        assert!(slug_ok("a1_-"));
        assert!(slug_ok("a"));
        assert!(!slug_ok(""));
        assert!(!slug_ok("-alerts"));
        assert!(!slug_ok("Alerts"));
        assert!(!slug_ok("alerts!"));
        assert!(!slug_ok(&"a".repeat(33)));
    }

    #[test]
    fn html_is_escaped() {
        assert_eq!(
            esc("<a href='x'>&\""),
            "&lt;a href=&#x27;x&#x27;&gt;&amp;&quot;"
        );
        assert_eq!(body_html("a\n<b>"), "a<br>&lt;b&gt;");
    }

    #[test]
    fn timestamps_are_iso8601_utc() {
        assert_eq!(iso8601_utc(0), "1970-01-01T00:00:00+00:00");
        assert_eq!(iso8601_utc(1_760_000_000), "2025-10-09T08:53:20+00:00");
    }

    #[test]
    fn form_decoding_handles_plus_and_percent() {
        assert_eq!(percent_decode("a+b"), "a b");
        assert_eq!(percent_decode("%D0%BF%D1%80%D0%B8"), "при");
        assert_eq!(
            parse_query("a=1&b=two%20words"),
            vec![
                ("a".to_string(), "1".to_string()),
                ("b".to_string(), "two words".to_string()),
            ]
        );
    }

    #[test]
    fn constant_time_comparison_is_still_a_comparison() {
        assert!(constant_time_eq(b"secret", b"secret"));
        assert!(!constant_time_eq(b"secret", b"secreT"));
        assert!(!constant_time_eq(b"secret", b"secret "));
    }

    #[test]
    fn text_rendering_matches_the_bbs_view() {
        let rows = vec![vec![
            ("slug".to_string(), Value::Text("alerts".to_string())),
            ("threads".to_string(), Value::Integer(2)),
            ("posts".to_string(), Value::Integer(5)),
            ("last".to_string(), Value::Null),
        ]];
        let text = as_text("boards", &rows);
        assert!(
            text.starts_with("alerts           2 threads 5 posts  -"),
            "{text}"
        );
    }
}
