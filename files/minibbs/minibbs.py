#!/usr/bin/env python3
"""minibbs -- a tiny BBS-style message board.

Boards hold threads, threads hold posts. The web UI is read-only on purpose:
bots write through the JSON API, humans read (HTML or ?fmt=txt for a plain-text
BBS view). Storage is a single SQLite file; the only dependency is Python's
standard library.

Configuration comes from the environment:
  MINIBBS_DB         path to the SQLite file
  MINIBBS_TOKEN_FILE file holding the bearer token required for posting
  MINIBBS_BIND       listen address
  MINIBBS_PORT       listen port
  MINIBBS_TITLE      title shown in the web UI

Posting:
  curl -sS -X POST http://<host>:<port>/api/post \\
    -H "Authorization: Bearer $(cat <token-file>)" \\
    -H 'Content-Type: application/json' \\
    -d '{"board":"alerts","author":"crashloop","subject":"MPD restarted","body":"..."}'
  Appending to an existing thread: add "thread": <id> and drop "subject".

Reading:
  GET /                      board list (HTML; ?fmt=txt for text)
  GET /b/<slug>              threads in a board
  GET /t/<id>                one thread
  GET /api/boards            JSON board list
  GET /api/board/<slug>      JSON threads (newest activity first)
  GET /api/thread/<id>       JSON posts
  GET /healthz               liveness
"""

import hmac
import html
import json
import os
import re
import sqlite3
import sys
import urllib.parse
from contextlib import closing
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DB = os.environ.get("MINIBBS_DB", "/var/lib/minibbs/bbs.sqlite")
TOKEN_FILE = os.environ.get("MINIBBS_TOKEN_FILE", "")
BIND = os.environ.get("MINIBBS_BIND", "127.0.0.1")
PORT = int(os.environ.get("MINIBBS_PORT", "8091"))
TITLE = os.environ.get("MINIBBS_TITLE", "minibbs")

MAX_BODY = 8192
MAX_SUBJECT = 200
MAX_AUTHOR = 64
SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,31}$")

SCHEMA = """
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
"""


def now():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def connect():
    """Open a SQLite connection.

    Use as `with closing(connect()) as conn, conn:` — the inner context commits
    on clean exit, the outer one always releases the file handle.
    """
    conn = sqlite3.connect(DB, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def init_db():
    with closing(connect()) as conn, conn:
        conn.executescript(SCHEMA)


def token_ok(supplied):
    """Compare against the token file on every request so rotation needs no restart."""
    if not TOKEN_FILE or not supplied:
        return False
    try:
        with open(TOKEN_FILE, "r", encoding="utf-8") as fh:
            expected = fh.read().strip()
    except OSError:
        return False
    return bool(expected) and hmac.compare_digest(expected, supplied)


def boards(conn):
    return conn.execute("""
        SELECT b.slug, b.title,
               (SELECT count(*) FROM threads t WHERE t.board_id = b.id) AS threads,
               (SELECT count(*) FROM posts p JOIN threads t ON t.id = p.thread_id
                 WHERE t.board_id = b.id) AS posts,
               (SELECT max(p.created) FROM posts p JOIN threads t ON t.id = p.thread_id
                 WHERE t.board_id = b.id) AS last
          FROM boards b
      ORDER BY b.slug
        """).fetchall()


def threads_of(conn, slug, limit=200):
    return conn.execute(
        """
        SELECT t.id, t.subject, t.created,
               (SELECT count(*) FROM posts p WHERE p.thread_id = t.id) AS posts,
               (SELECT p.author FROM posts p WHERE p.thread_id = t.id ORDER BY p.id LIMIT 1) AS author,
               (SELECT max(p.created) FROM posts p WHERE p.thread_id = t.id) AS last
          FROM threads t JOIN boards b ON b.id = t.board_id
         WHERE b.slug = ?
      ORDER BY last DESC, t.id DESC
         LIMIT ?
        """,
        (slug, limit),
    ).fetchall()


def thread_with_posts(conn, tid):
    thread = conn.execute(
        """
        SELECT t.id, t.subject, t.created, b.slug AS board
          FROM threads t JOIN boards b ON b.id = t.board_id
         WHERE t.id = ?
        """,
        (tid,),
    ).fetchone()
    if thread is None:
        return None, []
    posts = conn.execute(
        "SELECT id, author, body, created FROM posts WHERE thread_id = ? ORDER BY id",
        (tid,),
    ).fetchall()
    return thread, posts


def esc(value):
    return html.escape(str(value), quote=True)


def body_html(text):
    return "<br>".join(esc(line) for line in text.splitlines())


PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>
 body {{ background:#101014; color:#c8c8d0; font:14px/1.5 ui-monospace,monospace; margin:0; padding:24px; }}
 a {{ color:#7fdbca; text-decoration:none; }} a:hover {{ text-decoration:underline; }}
 h1 {{ font-size:18px; color:#e8e8f0; }} h2 {{ font-size:15px; margin:18px 0 6px; }}
 table {{ border-collapse:collapse; width:100%; }} td, th {{ text-align:left; padding:2px 12px 2px 0; vertical-align:top; }}
 .dim {{ color:#6a6a78; }} .post {{ border-left:2px solid #2a2a34; margin:12px 0; padding:2px 0 2px 12px; }}
 pre {{ white-space:pre-wrap; font:inherit; margin:4px 0; }}
</style></head><body>
<h1>{title}</h1>
<p class="dim">{crumbs}</p>
{content}
<p class="dim">read-only board &middot; bots post via <code>POST /api/post</code></p>
</body></html>"""


def page(crumbs, content, title=None):
    return PAGE.format(
        title=esc(title or TITLE), crumbs=crumbs, content=content
    )


def render_boards(rows):
    if not rows:
        return "<p>no boards yet</p>"
    out = [
        "<table><tr><th>board</th><th>threads</th><th>posts</th><th>last</th></tr>"
    ]
    for r in rows:
        out.append(
            f"<tr><td><a href='/b/{esc(r['slug'])}'>{esc(r['slug'])}</a></td>"
            f"<td>{r['threads']}</td><td>{r['posts']}</td>"
            f"<td class='dim'>{esc(r['last'] or '-')}</td></tr>"
        )
    return "\n".join(out) + "</table>"


def render_threads(slug, rows):
    if not rows:
        return f"<p>board <b>{esc(slug)}</b> is empty</p>"
    out = [
        f"<h2>{esc(slug)}</h2>",
        "<table><tr><th>#</th><th>subject</th><th>posts</th><th>last</th></tr>",
    ]
    for r in rows:
        out.append(
            f"<tr><td><a href='/t/{r['id']}'>{r['id']}</a></td>"
            f"<td>{esc(r['subject'])}</td><td>{r['posts']}</td>"
            f"<td class='dim'>{esc(r['last'] or '-')} {esc(r['author'] or '')}</td></tr>"
        )
    return "\n".join(out) + "</table>"


def render_posts(thread, posts):
    out = [f"<h2>#{thread['id']} {esc(thread['subject'])}</h2>"]
    for p in posts:
        out.append(
            f"<div class='post'><p class='dim'>#{p['id']} {esc(p['author'])} &middot; "
            f"{esc(p['created'])}</p><pre>{body_html(p['body'])}</pre></div>"
        )
    return "\n".join(out)


def as_text(kind, rows):
    """Plain-text rendering for ?fmt=txt and clients that ask for text."""
    lines = []
    if kind == "boards":
        for r in rows:
            lines.append(
                f"{r['slug']:<16} {r['threads']} threads {r['posts']} posts  {r['last'] or '-'}"
            )
    else:
        for r in rows:
            lines.append(
                f"#{r['id']:<5} {r['subject']}  ({r['posts']} posts, last {r['last'] or '-'})"
            )
    return "\n".join(lines) + "\n"


class Handler(BaseHTTPRequestHandler):
    server_version = "minibbs/1"
    protocol_version = "HTTP/1.1"

    # -- plumbing ---------------------------------------------------------

    def reply(self, code, body, ctype="text/html; charset=utf-8"):
        payload = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def reply_json(self, code, obj):
        self.reply(
            code,
            json.dumps(obj, ensure_ascii=False) + "\n",
            "application/json; charset=utf-8",
        )

    def wants_text(self):
        query = urllib.parse.urlparse(self.path).query
        params = urllib.parse.parse_qs(query)
        if params.get("fmt", [""])[0] == "txt":
            return True
        return "text/plain" in self.headers.get("Accept", "")

    def parts(self):
        parsed = urllib.parse.urlparse(self.path)
        return parsed.path.rstrip("/") or "/", urllib.parse.parse_qs(
            parsed.query
        )

    # -- GET --------------------------------------------------------------

    def do_GET(self):  # noqa: N802 (BaseHTTPRequestHandler naming)
        path, params = self.parts()
        try:
            with closing(connect()) as conn, conn:
                if path in ("/", "/index.html"):
                    rows = boards(conn)
                    if self.wants_text():
                        return self.reply(
                            200,
                            as_text("boards", rows),
                            "text/plain; charset=utf-8",
                        )
                    return self.reply(200, page("boards", render_boards(rows)))
                if path == "/healthz":
                    return self.reply(200, "ok\n", "text/plain; charset=utf-8")
                if path == "/api/boards":
                    return self.reply_json(
                        200, {"boards": [dict(r) for r in boards(conn)]}
                    )
                if path.startswith("/b/"):
                    slug = path[3:]
                    rows = threads_of(conn, slug)
                    if self.wants_text():
                        return self.reply(
                            200,
                            as_text("threads", rows),
                            "text/plain; charset=utf-8",
                        )
                    return self.reply(
                        200,
                        page(
                            f"boards / <a href='/b/{esc(slug)}'>{esc(slug)}</a>",
                            render_threads(slug, rows),
                        ),
                    )
                if path.startswith("/api/board/"):
                    slug = path[len("/api/board/") :]
                    try:
                        limit = min(int(params.get("limit", ["100"])[0]), 500)
                    except ValueError:
                        limit = 100
                    rows = threads_of(conn, slug, limit=limit)
                    return self.reply_json(
                        200,
                        {"board": slug, "threads": [dict(r) for r in rows]},
                    )
                if path.startswith("/t/") or path.startswith("/api/thread/"):
                    api = path.startswith("/api/")
                    tid = path[len("/api/thread/") :] if api else path[3:]
                    thread, posts = thread_with_posts(conn, tid)
                    if thread is None:
                        if api:
                            return self.reply_json(
                                404, {"error": "no such thread"}
                            )
                        return self.reply(
                            404, page("boards", "<p>no such thread</p>")
                        )
                    if api:
                        return self.reply_json(
                            200,
                            {
                                "thread": dict(thread),
                                "posts": [dict(p) for p in posts],
                            },
                        )
                    return self.reply(
                        200,
                        page(
                            f"boards / <a href='/b/{esc(thread['board'])}'>{esc(thread['board'])}</a> / "
                            f"#{thread['id']}",
                            render_posts(thread, posts),
                        ),
                    )
        except BrokenPipeError:
            return
        self.reply_json(404, {"error": "not found"})

    # -- POST -------------------------------------------------------------

    def do_POST(self):  # noqa: N802
        path, params = self.parts()
        if path not in ("/api/post", "/api/post/"):
            return self.reply_json(404, {"error": "not found"})

        header = self.headers.get("Authorization", "")
        token = (
            header[7:]
            if header.lower().startswith("bearer ")
            else params.get("token", [""])[0]
        )
        if not token_ok(token):
            return self.reply_json(401, {"error": "invalid or missing token"})

        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_BODY * 2:
            return self.reply_json(413, {"error": "payload too large"})
        raw = (
            self.rfile.read(length).decode("utf-8", "replace")
            if length
            else ""
        )
        try:
            if "application/json" in self.headers.get("Content-Type", ""):
                fields = json.loads(raw or "{}")
            else:
                fields = {
                    k: v[0] for k, v in urllib.parse.parse_qs(raw).items()
                }
                fields.update(
                    {k: v[0] for k, v in params.items() if k != "token"}
                )
        except (ValueError, TypeError):
            return self.reply_json(
                400, {"error": "body must be JSON or form-encoded"}
            )

        board = str(fields.get("board", "")).strip().lower()
        author = str(fields.get("author", "") or "anon").strip()[:MAX_AUTHOR]
        subject = str(fields.get("subject", "") or "").strip()[:MAX_SUBJECT]
        body = str(fields.get("body", "") or "").strip()
        thread_id = fields.get("thread")

        if not SLUG_RE.match(board):
            return self.reply_json(
                400, {"error": "board must match [a-z0-9][a-z0-9_-]{0,31}"}
            )
        if not body:
            return self.reply_json(400, {"error": "body is required"})
        if len(body) > MAX_BODY:
            return self.reply_json(
                413, {"error": f"body limited to {MAX_BODY} bytes"}
            )
        if not subject:
            subject = body.splitlines()[0][:60]

        created = now()
        with closing(connect()) as conn, conn:
            conn.execute(
                "INSERT INTO boards(slug, title, created) VALUES(?, ?, ?) ON CONFLICT(slug) DO NOTHING",
                (board, board, created),
            )
            board_id = conn.execute(
                "SELECT id FROM boards WHERE slug = ?", (board,)
            ).fetchone()["id"]
            if thread_id:
                row = conn.execute(
                    "SELECT id FROM threads WHERE id = ? AND board_id = ?",
                    (thread_id, board_id),
                ).fetchone()
                if row is None:
                    return self.reply_json(
                        404, {"error": "no such thread in this board"}
                    )
                tid = row["id"]
            else:
                tid = conn.execute(
                    "INSERT INTO threads(board_id, subject, created) VALUES(?, ?, ?)",
                    (board_id, subject, created),
                ).lastrowid
            pid = conn.execute(
                "INSERT INTO posts(thread_id, author, body, created) VALUES(?, ?, ?, ?)",
                (tid, author, body, created),
            ).lastrowid
        self.reply_json(
            201,
            {
                "ok": True,
                "board": board,
                "thread": tid,
                "post": pid,
                "url": f"/t/{tid}",
            },
        )

    def log_message(
        self, fmt, *args
    ):  # keep journald output short, one line per request
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


def main():
    init_db()
    with ThreadingHTTPServer((BIND, PORT), Handler) as httpd:
        httpd.daemon_threads = True
        print(f"minibbs listening on {BIND}:{PORT} db={DB}", flush=True)
        httpd.serve_forever()


if __name__ == "__main__":
    main()
