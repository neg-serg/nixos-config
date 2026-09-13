import json
import pathlib
import subprocess
import sys
import time

# Shared with the Quickshell PillTracker (panel pill capsule).
PANEL_STATE_FILE = pathlib.Path("@panelStateFile@")

# Idempotency guard: on this VM snapshot restores / late boot catch-ups can
# fire the timer more than once a day. Stamp the date on every successful
# send and skip if we already reminded today, so it is at most once/24h.
STATE_DIR = pathlib.Path("/var/lib/telegram-pill-reminder")
MARKER = STATE_DIR / "last-sent.txt"
LAST_MSG_FILE = STATE_DIR / "last-message.json"
TODAY = time.strftime("%Y-%m-%d")


def already_taken_today():
    try:
        state = json.loads(PANEL_STATE_FILE.read_text())
    except (OSError, ValueError):
        return False
    return state.get("todayDate") == TODAY and bool(state.get("taken"))


if already_taken_today():
    print("pill-reminder: pill already taken today, skipping")
    sys.exit(0)

try:
    if MARKER.read_text().strip() == TODAY:
        print("pill-reminder: already sent today, skipping")
        sys.exit(0)
except FileNotFoundError:
    pass

TOKEN = open("@botTokenPath@").read().strip()
CHAT_ID = open("@chatIdPath@").read().strip()
CURL = "/run/current-system/sw/bin/curl"
API = "https://api.telegram.org/bot{0}/sendMessage".format(TOKEN)
MARKUP = json.dumps(
    {
        "inline_keyboard": [
            [{"text": "Отметить ✅", "callback_data": "pill_taken"}]
        ]
    }
)
TEXT = "💊 12:00 — пора принять таблетку. Нажми «Отметить», когда принял."

for attempt in range(12):
    proc = subprocess.run(
        [
            CURL,
            "-s",
            "--proxy",
            "socks5h://127.0.0.1:10808",
            "--data-urlencode",
            "chat_id={0}".format(CHAT_ID),
            "--data-urlencode",
            "text={0}".format(TEXT),
            "--data-urlencode",
            "reply_markup={0}".format(MARKUP),
            API,
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode == 0:
        MARKER.parent.mkdir(parents=True, exist_ok=True)
        MARKER.write_text(TODAY)
        # Remember the sent message so a later panel-side "taken" can edit
        # the same message and keep panel and chat confirmations in sync.
        try:
            sent = json.loads(proc.stdout or "{}")
            message_id = sent.get("result", {}).get("message_id")
            if message_id:
                LAST_MSG_FILE.write_text(
                    json.dumps(
                        {
                            "date": TODAY,
                            "chat_id": CHAT_ID,
                            "message_id": message_id,
                            "confirmed": False,
                        }
                    )
                )
        except (OSError, ValueError):
            print(
                "pill-reminder: could not record sent message id",
                file=sys.stderr,
            )
        sys.exit(0)
    time.sleep(5)
print("pill-reminder: could not deliver after 12 attempts", file=sys.stderr)
sys.exit(1)
