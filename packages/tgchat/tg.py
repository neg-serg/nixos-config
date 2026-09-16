#!/usr/bin/env python3
"""Telegram chat access for the agent and the user (Telethon, user session).

Credentials come from gopass (`api/telegram-telethon-id` /
`api/telegram-telethon-hash`) or from TELEGRAM_API_ID / TELEGRAM_API_HASH.
The authorized session lives in ~/.local/state/telegram-chat/, so a login
survives rebuilds. Telegram is reached through the local sing-box socks
proxy by default (the MTProto endpoints are not reachable from this host
without it); override with TELEGRAM_PROXY, disable with TELEGRAM_PROXY=off.

Commands: login (QR by default), whoami, dialogs, tail, search, send.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse

STATE_DIR = Path(
    os.environ.get("TGCHAT_STATE", "~/.local/state/telegram-chat")
).expanduser()
SESSION = STATE_DIR / "session"
LOGIN_STATE = STATE_DIR / "login.json"
QR_PNG = STATE_DIR / "qr.png"
DEFAULT_PROXY = "socks5://127.0.0.1:10808"


def die(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(1)


def secret(name: str) -> str:
    """Read one secret: env override, gopass lookup, gpg fallback."""
    env = {
        "api/telegram-telethon-id": "TELEGRAM_API_ID",
        "api/telegram-telethon-hash": "TELEGRAM_API_HASH",
    }[name]
    value = os.environ.get(env, "").strip()
    if value:
        return value
    try:
        out = subprocess.run(
            ["gopass", "show", "-o", name],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    store = Path(
        os.environ.get("PASSWORD_STORE_DIR", "~/.local/share/pass")
    ).expanduser()
    blob = store / f"{name}.gpg"
    if blob.exists():
        out = subprocess.run(
            ["gpg", "--batch", "--quiet", "--decrypt", str(blob)],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    die(f"cannot read {name} (gopass/gpg and ${env} failed)")


def credentials() -> "tuple[int, str]":
    return int(secret("api/telegram-telethon-id")), secret(
        "api/telegram-telethon-hash"
    )


def proxy_config() -> "None | tuple":
    raw = os.environ.get("TELEGRAM_PROXY", DEFAULT_PROXY).strip()
    if raw.lower() in ("", "off", "none"):
        return None
    parts = urlparse(raw if "://" in raw else f"socks5://{raw}")
    if parts.scheme not in ("socks5", "socks4", "http"):
        die(f"unsupported proxy scheme: {parts.scheme}")
    return (
        parts.scheme,
        parts.hostname or "127.0.0.1",
        parts.port or 1080,
        True,  # rdns: resolve names remotely (DNS is unreliable here)
        parts.username,
        parts.password,
    )


def client():
    from telethon import TelegramClient

    api_id, api_hash = credentials()
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    return TelegramClient(str(SESSION), api_id, api_hash, proxy=proxy_config())


def stamp(moment: "datetime | None") -> str:
    if moment is None:
        return "?"
    return moment.astimezone().strftime("%Y-%m-%d %H:%M")


def one_line(text: str, width: int = 300) -> str:
    flat = " ".join((text or "").split())
    return flat if len(flat) <= width else flat[: width - 1] + "…"


async def resolve(cli, name: str):
    """Accept an id, @username, t.me link, phone or a title substring."""
    if not name:
        return None
    try:
        return await cli.get_entity(int(name))
    except ValueError:
        pass
    except Exception:  # noqa: BLE001 - not an id, fall through to lookup
        pass
    if name.startswith("@") or name.startswith("+") or "/" in name:
        try:
            return await cli.get_entity(name)
        except Exception as exc:  # noqa: BLE001
            die(f"cannot resolve {name}: {exc}")
    needle = name.casefold()
    matches = []
    async for dialog in cli.iter_dialogs():
        if needle in (dialog.name or "").casefold():
            matches.append(dialog.entity)
    if len(matches) == 1:
        return matches[0]
    if not matches:
        die(f"no dialog matches {name!r}")
    titles = ", ".join(getattr(m, "title", "?") or "?" for m in matches)
    die(f"{name!r} is ambiguous: {titles}")


async def render_message(cli, msg) -> dict:
    sender = None
    try:
        sender = await msg.get_sender()
    except Exception:  # noqa: BLE001 - sender may be unavailable
        sender = None
    name = getattr(sender, "first_name", None)
    if not name:
        name = getattr(sender, "title", None) or getattr(
            sender, "username", None
        )
    if not name:
        name = str(msg.sender_id) if msg.sender_id else "?"
    return {
        "id": msg.id,
        "date": stamp(msg.date),
        "sender": name,
        "out": bool(msg.out),
        "text": msg.text or _media_label(msg),
    }


def _media_label(msg) -> str:
    for attr, label in (
        ("photo", "[photo]"),
        ("voice", "[voice]"),
        ("video_note", "[video note]"),
        ("video", "[video]"),
        ("audio", "[audio]"),
        ("sticker", "[sticker]"),
        ("document", "[document]"),
        ("poll", "[poll]"),
        ("geo", "[geo]"),
    ):
        if getattr(msg, attr, None):
            return label
    return "[service]" if msg.action else "[no text]"


async def cmd_login(args) -> int:
    cli = client()
    await cli.connect()
    if await cli.is_user_authorized():
        me = await cli.get_me()
        print(f"already authorized as {me.first_name} (id={me.id})")
        await cli.disconnect()
        return 0
    if args.phone and args.code:
        state = (
            json.loads(LOGIN_STATE.read_text()) if LOGIN_STATE.exists() else {}
        )
        if state.get("phone") != args.phone or "hash" not in state:
            die("run `login --phone <number>` first to request a code")
        try:
            await cli.sign_in(
                phone=args.phone,
                code=args.code,
                phone_code_hash=state["hash"],
            )
        except Exception as exc:  # noqa: BLE001
            from telethon.errors import SessionPasswordNeededError

            if isinstance(exc, SessionPasswordNeededError):
                if not args.password:
                    die("2FA enabled: pass --password <your password>")
                await cli.sign_in(password=args.password)
            else:
                die(f"sign-in failed: {exc}")
        me = await cli.get_me()
        print(f"authorized as {me.first_name} (id={me.id})")
        LOGIN_STATE.unlink(missing_ok=True)
        await cli.disconnect()
        return 0
    if args.phone:
        sent = await cli.send_code_request(args.phone)
        LOGIN_STATE.write_text(
            json.dumps({"phone": args.phone, "hash": sent.phone_code_hash})
        )
        print(f"code sent to {args.phone}; rerun with --code")
        await cli.disconnect()
        return 0
    return await qr_login(cli, args)


def two_factor_password(args) -> str:
    """2FA password: --password, $TELEGRAM_2FA or an interactive prompt."""
    password = args.password or os.environ.get("TELEGRAM_2FA", "")
    if password:
        return password
    if sys.stdin.isatty():
        import getpass

        return getpass.getpass("2FA password: ")
    die(
        "2FA is enabled: pass --password, set $TELEGRAM_2FA or run interactively"
    )


def needs_two_factor(exc: Exception) -> bool:
    from telethon.errors import SessionPasswordNeededError

    return isinstance(exc, SessionPasswordNeededError)


async def qr_login(cli, args) -> int:
    """QR flow: write a PNG the user scans in Telegram -> Devices.

    With two-step verification enabled the approved token still needs the
    account password (Telegram requires it before exporting the login token),
    so the password is collected here and the sign-in finished with it.
    """
    qr = await cli.qr_login()
    print("scan the QR in Telegram: Settings -> Devices -> Link Desktop")
    while not await cli.is_user_authorized():
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        out = subprocess.run(
            ["qrencode", "-o", str(QR_PNG), "-s", "6", "-m", "2", qr.url],
            capture_output=True,
            text=True,
        )
        if out.returncode != 0:
            die(f"qrencode failed: {out.stderr.strip() or 'not installed'}")
        print(f"QR file: {QR_PNG}", flush=True)
        try:
            await qr.wait(timeout=25)
        except asyncio.TimeoutError:
            try:
                await qr.recreate()
            except Exception as exc:  # noqa: BLE001 - 2FA surfaces here
                if needs_two_factor(exc):
                    await cli.sign_in(password=two_factor_password(args))
                    break
                raise
        except Exception as exc:  # noqa: BLE001 - 2FA surfaces here too
            if not needs_two_factor(exc):
                raise
            await cli.sign_in(password=two_factor_password(args))
            break
    me = await cli.get_me()
    print(f"authorized as {me.first_name} (id={me.id})")
    QR_PNG.unlink(missing_ok=True)
    await cli.disconnect()
    return 0


async def cmd_whoami(cli, args) -> int:
    me = await cli.get_me()
    print(
        json.dumps(
            {
                "id": me.id,
                "first_name": me.first_name,
                "last_name": me.last_name,
                "username": me.username,
                "phone": me.phone,
            },
            ensure_ascii=False,
            indent=2,
        )
        if args.json
        else f"{me.first_name} {me.last_name or ''} (@{me.username}) "
        f"id={me.id}"
    )
    return 0


async def cmd_dialogs(cli, args) -> int:
    rows = []
    async for d in cli.iter_dialogs(limit=args.limit):
        rows.append(
            {
                "id": d.id,
                "title": d.name,
                "unread": d.unread_count,
                "last": one_line(getattr(d.message, "text", "") or ""),
                "when": stamp(getattr(d.message, "date", None)),
            }
        )
    if args.json:
        print(json.dumps(rows, ensure_ascii=False, indent=2))
        return 0
    for r in rows:
        unread = f" ({r['unread']} unread)" if r["unread"] else ""
        print(f"{r['id']:>14}  {r['when']}  {r['title']}{unread}")
        if r["last"]:
            print(f"{'':>14}  · {r['last']}")
    return 0


async def cmd_tail(cli, args) -> int:
    entity = await resolve(cli, args.chat)
    if entity is None:
        die("tail needs a chat (see `dialogs`)")
    msgs = await cli.get_messages(entity, limit=args.number)
    rows = [await render_message(cli, m) for m in reversed(msgs)]
    if args.json:
        print(json.dumps(rows, ensure_ascii=False, indent=2))
        return 0
    for r in rows:
        who = "me" if r["out"] else r["sender"]
        print(f"[{r['date']}] {who}: {r['text']}")
    return 0


async def cmd_search(cli, args) -> int:
    entity = await resolve(cli, args.chat) if args.chat else None
    rows = []
    async for msg in cli.iter_messages(
        entity, search=args.query, limit=args.number
    ):
        rows.append(await render_message(cli, msg))
    if args.json:
        print(json.dumps(rows, ensure_ascii=False, indent=2))
        return 0
    for r in rows:
        who = "me" if r["out"] else r["sender"]
        print(f"[{r['date']}] {who}: {r['text']}")
    return 0


async def cmd_send(cli, args) -> int:
    entity = await resolve(cli, args.chat)
    if entity is None:
        die("send needs a chat")
    text = " ".join(args.text)
    if not text and not args.file:
        die("nothing to send")
    msg = await cli.send_message(
        entity, text, file=args.file, reply_to=args.reply_to
    )
    print(f"sent id={msg.id} to {args.chat}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="tgchat", description="Telegram chat access via Telethon"
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("login", help="authorize the session (QR by default)")
    p.add_argument("--phone", help="phone number for the code flow")
    p.add_argument("--code", help="code received by SMS/app")
    p.add_argument("--password", help="2FA password, if enabled")
    p.set_defaults(func=cmd_login, needs_client=False)

    p = sub.add_parser("whoami", help="show the authorized account")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_whoami)

    p = sub.add_parser("dialogs", help="list chats by recency")
    p.add_argument("--limit", type=int, default=20)
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_dialogs)

    p = sub.add_parser("tail", help="last messages of a chat")
    p.add_argument("chat", nargs="?", help="id, @username, t.me link, title")
    p.add_argument("-n", "--number", type=int, default=20)
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_tail)

    p = sub.add_parser("search", help="search messages")
    p.add_argument("query")
    p.add_argument("--chat", help="limit to one chat")
    p.add_argument("-n", "--number", type=int, default=20)
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_search)

    p = sub.add_parser("send", help="send a message")
    p.add_argument("chat")
    p.add_argument("text", nargs="*")
    p.add_argument("--file", help="attach a file")
    p.add_argument("--reply-to", type=int)
    p.set_defaults(func=cmd_send)
    return parser


async def run(args) -> int:
    if args.func is cmd_login:
        return await cmd_login(args)
    cli = client()
    await cli.connect()
    if not await cli.is_user_authorized():
        await cli.disconnect()
        die("session not authorized — run `tgchat login` (QR)")
    try:
        return await args.func(cli, args)
    finally:
        await cli.disconnect()


def main() -> int:
    args = build_parser().parse_args()
    try:
        return asyncio.run(run(args))
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
