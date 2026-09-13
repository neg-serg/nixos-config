import json
import os
import pathlib
import pwd
import subprocess
import sys
import time

TOKEN_FILE = "@botTokenPath@"
CHAT_ID_FILE = "@chatIdPath@"
CURL = "/run/current-system/sw/bin/curl"
PROXY = "socks5h://127.0.0.1:10808"
STATE_DIR = pathlib.Path("/var/lib/telegram-pill-bot")
OFFSET_FILE = STATE_DIR / "offset"
LOG_FILE = STATE_DIR / "pill-log.txt"
LAST_MSG_FILE = pathlib.Path(
    "/var/lib/telegram-pill-reminder/last-message.json"
)

# Quickshell PillTracker files owned by the desktop user's panel.
PANEL_STATE_FILE = pathlib.Path("@panelStateFile@")
PANEL_ICS_DIR = pathlib.Path("@panelIcsDir@")
PILL_OWNER = "@panelUser@"

# Must match telegram-pill-reminder.py: used to restore the reminder
# message (with its button) when the panel mark is reverted.
REMINDER_TEXT = (
    "💊 12:00 — пора принять таблетку. Нажми «Отметить», когда принял."
)
REMINDER_MARKUP = json.dumps(
    {
        "inline_keyboard": [
            [{"text": "Отметить ✅", "callback_data": "pill_taken"}]
        ]
    }
)
CONFIRMED_TEXT = "💊 Принято ✅ ({0})"


def read_secrets():
    token = open(TOKEN_FILE).read().strip()
    chat_id = open(CHAT_ID_FILE).read().strip()
    return token, chat_id


def api_call(method, params, token):
    cmd = [CURL, "-s", "--proxy", PROXY, "--max-time", "70"]
    for key, value in params.items():
        cmd += ["--data-urlencode", "{0}={1}".format(key, value)]
    cmd.append("https://api.telegram.org/bot{0}/{1}".format(token, method))
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


def stamp_now():
    return time.strftime("%Y-%m-%d %H:%M %Z")


def owner_ids():
    pw = pwd.getpwnam(PILL_OWNER)
    return pw.pw_uid, pw.pw_gid


def read_panel_state():
    try:
        return json.loads(PANEL_STATE_FILE.read_text())
    except (OSError, ValueError):
        return {}


def write_panel_state(state):
    uid, gid = owner_ids()
    PANEL_STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    PANEL_STATE_FILE.write_text(json.dumps(state, indent=4) + "\n")
    os.chown(PANEL_STATE_FILE, uid, gid)
    os.chmod(PANEL_STATE_FILE, 0o644)


def write_panel_ics(today, taken_at):
    uid, gid = owner_ids()
    PANEL_ICS_DIR.mkdir(parents=True, exist_ok=True)
    path = PANEL_ICS_DIR / ("pill-" + today + ".ics")
    dtstart = today.replace("-", "")
    ics = "\r\n".join(
        [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Neg//PillTracker//EN",
            "BEGIN:VEVENT",
            "DTSTART;VALUE=DATE:" + dtstart,
            "DTEND;VALUE=DATE:" + dtstart,
            "SUMMARY:Pill \u2705",
            "DESCRIPTION:Taken at " + taken_at,
            "CATEGORIES:Health",
            "END:VEVENT",
            "END:VCALENDAR",
            "",
        ]
    )
    path.write_text(ics)
    os.chown(path, uid, gid)
    os.chmod(path, 0o644)
    # The collection dir may have been created above as root; hand it
    # back to the desktop user so vdirsyncer stays writable.
    st = os.stat(PANEL_ICS_DIR)
    if (st.st_uid, st.st_gid) != (uid, gid):
        os.chown(PANEL_ICS_DIR, uid, gid)


def remove_panel_ics(today):
    (PANEL_ICS_DIR / ("pill-" + today + ".ics")).unlink(missing_ok=True)


def mark_panel_taken(today, taken_at):
    state = read_panel_state()
    state["todayDate"] = today
    state["taken"] = True
    state["takenAt"] = taken_at
    if not isinstance(state.get("history"), list):
        state["history"] = []
    write_panel_state(state)
    write_panel_ics(today, taken_at)


def last_message(today):
    try:
        data = json.loads(LAST_MSG_FILE.read_text())
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict) or data.get("date") != today:
        return None
    data.setdefault("confirmed", False)
    return data


def save_last_message(data):
    LAST_MSG_FILE.parent.mkdir(parents=True, exist_ok=True)
    LAST_MSG_FILE.write_text(json.dumps(data))


def log_line(text):
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    with LOG_FILE.open("a") as fh:
        fh.write(text + "\n")


def edit_message(msg, text, token, reply_markup=None):
    params = {
        "chat_id": str(msg["chat_id"]),
        "message_id": str(msg["message_id"]),
        "text": text,
    }
    if reply_markup is not None:
        params["reply_markup"] = reply_markup
    return api_call("editMessageText", params, token)


def sync_from_panel(today, token):
    """Converge the day's Telegram reminder message on the panel state."""
    msg = last_message(today)
    if not msg:
        return
    state = read_panel_state()
    taken = state.get("todayDate") == today and bool(state.get("taken"))
    if msg.get("confirmed") == taken:
        return
    if taken:
        taken_at = state.get("takenAt") or time.strftime("%H:%M")
        resp = edit_message(
            msg, CONFIRMED_TEXT.format(today + " " + taken_at), token
        )
    else:
        resp = edit_message(msg, REMINDER_TEXT, token, REMINDER_MARKUP)
    if resp.returncode == 0:
        msg["confirmed"] = taken
        save_last_message(msg)
        if taken:
            log_line(stamp_now())


offset = 0
if OFFSET_FILE.exists():
    try:
        offset = int(OFFSET_FILE.read_text().strip())
    except ValueError:
        offset = 0

while True:
    try:
        token, chat_id = read_secrets()
        today = time.strftime("%Y-%m-%d")

        # Bridge: panel-side marks edit the Telegram reminder message and
        # Telegram-side marks update the panel capsule/calendar. Converging
        # on the recorded confirmation also heals any half-applied state.
        sync_from_panel(today, token)

        resp = api_call(
            "getUpdates", {"offset": str(offset + 1), "timeout": "25"}, token
        )
        if resp.returncode != 0:
            time.sleep(5)
            continue
        data = json.loads(resp.stdout or "{}")
        if not data.get("ok"):
            time.sleep(5)
            continue
        for update in data.get("result", []):
            offset = max(offset, update.get("update_id", 0))
            callback = update.get("callback_query")
            message = update.get("message") or {}
            if not callback and message:
                # Log who talks to the bot so the owner id can be captured.
                sender = message.get("from", {})
                chat = message.get("chat", {})
                print(
                    "pill-bot: message from {0} in chat {1} (type {2})".format(
                        sender.get("id"), chat.get("id"), chat.get("type")
                    ),
                    file=sys.stderr,
                )
            if not callback:
                continue
            # Private-chat bot: only presses from the owner count. In a
            # 1:1 chat both chat.id and from.id equal the user id, which
            # is the chat id the reminders go to; ignore anything else.
            cb_message = callback.get("message", {})
            cb_chat = cb_message.get("chat", {})
            chat_id_n = cb_chat.get("id")
            from_id = callback.get("from", {}).get("id")
            if str(chat_id_n) != chat_id or str(from_id) != chat_id:
                continue
            query_id = callback.get("id", "")
            data_field = callback.get("data", "")
            api_call(
                "answerCallbackQuery",
                {"callback_query_id": query_id},
                token,
            )
            if data_field == "pill_taken":
                message_id = cb_message.get("message_id")
                if message_id:
                    taken_at = stamp_now()
                    # Record in the panel first: the capsule lights up and
                    # the day is marked in the vdirsyncer calendar. If the
                    # Telegram-side edit below fails, sync_from_panel heals
                    # it on the next pass.
                    mark_panel_taken(today, time.strftime("%H:%M"))
                    api_call(
                        "editMessageText",
                        {
                            "chat_id": chat_id_n,
                            "message_id": message_id,
                            "text": CONFIRMED_TEXT.format(taken_at),
                        },
                        token,
                    )
                    # Remember the message so later panel-side changes can
                    # edit it back (button restore on unmark).
                    msg = last_message(today)
                    if not msg:
                        msg = {
                            "date": today,
                            "chat_id": chat_id_n,
                            "message_id": message_id,
                        }
                    if msg.get("message_id") == message_id:
                        msg["confirmed"] = True
                        save_last_message(msg)
                    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
                    with LOG_FILE.open("a") as fh:
                        fh.write(taken_at + "\n")
        OFFSET_FILE.write_text(str(offset))
    except Exception as exc:
        print("pill-bot: {0}".format(exc), file=sys.stderr)
        time.sleep(5)
