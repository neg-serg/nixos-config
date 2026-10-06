set -euo pipefail

TELEGRAM_BOT_TOKEN_FILE="@botTokenPath@"
TELEGRAM_CHAT_ID_FILE="@chatIdPath@"
# Re-read the secrets on every request so a chat-id change takes
# effect without restarting the bridge.
export TELEGRAM_BOT_TOKEN_FILE TELEGRAM_CHAT_ID_FILE

exec python3 -c '
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
import subprocess

# Bracketed status/severity words ([FIRING] [INFO] …) read badly in a phone
# push, so each is one emoji with no space between them: status first, severity
# second. The severity emoji is kept only for warning/critical (info carries no
# news) and any unknown value falls back to ❔, so a push stays one short line.
STATUS_EMOJI = {"firing": "🔥", "resolved": "✅"}
SEVERITY_EMOJI = {"critical": "🚨", "warning": "⚠️"}


def creds():
    token = open(os.environ["TELEGRAM_BOT_TOKEN_FILE"]).read().strip()
    chat_id = open(os.environ["TELEGRAM_CHAT_ID_FILE"]).read().strip()
    return token, chat_id


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        data = json.loads(self.rfile.read(length))
        for alert in data.get("alerts", []):
            status_emoji = STATUS_EMOJI.get(str(alert.get("status", "")).lower(), "❔")
            labels = alert.get("labels", {})
            annotations = alert.get("annotations", {})
            name = labels.get("alertname", "Unknown")
            severity = labels.get("severity", "unknown")
            summary = annotations.get("summary", "No summary")
            severity_emoji = SEVERITY_EMOJI.get(str(severity).lower(), "")
            msg = "{0}{1} {2}: {3}".format(status_emoji, severity_emoji, name, summary)
            token, chat_id = creds()
            api_url = "https://api.telegram.org/bot{0}/sendMessage".format(token)
            # api.telegram.org is unreachable from this host without the
            # sing-box socks proxy (socks5h://127.0.0.1:10808).
            # The URL carries the bot token and /proc/<pid>/cmdline is
            # world-readable, so feed the URL to curl through a "-K -"
            # stdin config instead of argv (tokens are [0-9A-Za-z_:-]).
            subprocess.run(
                [
                    "/run/current-system/sw/bin/curl",
                    "-s", "-o", "/dev/null",
                    "--proxy", "socks5h://127.0.0.1:10808",
                    "-K", "-",
                    "--data-urlencode", "chat_id={0}".format(chat_id),
                    "--data-urlencode", "text={0}".format(msg),
                ],
                input=("url = \"{0}\"\n".format(api_url)).encode(),
                check=False,
            )
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

    def log_message(self, format, *args):
        pass


HTTPServer(("127.0.0.1", 9094), Handler).serve_forever()
'
