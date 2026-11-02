#!/usr/bin/env python3
"""Local stand-in for date.nager.at and isdayoff.ru, used by tests/parity.sh.

It logs every request line (method, path, User-Agent) as JSON lines and can be
told to fail, to answer a custom body, or to stall, so the harness can compare
the shell worker and the Rust port on the same input:

    mock_http.py --port-file FILE --log FILE [--holidays-status N]
                 [--holidays-body TEXT] [--workdays-status N]
                 [--workdays-body TEXT] [--delay SECONDS]
                 [--delay-route holidays|workdays]

The listener binds 127.0.0.1:0 and writes the chosen port to --port-file, so
the harness never guesses a port. Dev-only tooling: it is not part of the
package build.
"""

import argparse
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOLIDAYS = (
    '[{"date":"2026-11-04","localName":"Den narodnogo edinstva",'
    '"name":"Unity Day","countryCode":"RU","fixed":true,"global":true,'
    '"counties":null,"launchYear":2005,"types":["Public"]},'
    '{"date":"2026-12-31","localName":"New Year","name":"New Year",'
    '"countryCode":"RU","fixed":true,"global":true,"counties":null,'
    '"launchYear":null,"types":["Public"]}]'
)

WORKDAYS = "000010000000000000000000000000"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "pleamar-calendar-mock"

    def do_GET(self):  # noqa: N802 - http.server's spelling
        path = self.path
        with self.server.lock:
            self.server.log.write(
                json.dumps(
                    {
                        "method": "GET",
                        "path": path,
                        "ua": self.headers.get("User-Agent", ""),
                    },
                    ensure_ascii=False,
                )
                + "\n"
            )
            self.server.log.flush()

        if (
            path.startswith("/api/v3/PublicHolidays/")
            or "/PublicHolidays/" in path
        ):
            status = self.server.holidays_status
            body = self.server.holidays_body
            route = "holidays"
        elif path.startswith("/api/getdata") or "/getdata" in path:
            status = self.server.workdays_status
            body = self.server.workdays_body
            route = "workdays"
        else:
            status, body, route = 404, "not found", "other"

        if self.server.delay > 0 and route == self.server.delay_route:
            time.sleep(self.server.delay)

        payload = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *args):  # keep the harness output clean
        pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port-file", required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--holidays-status", type=int, default=200)
    parser.add_argument("--holidays-body", default=HOLIDAYS)
    parser.add_argument("--workdays-status", type=int, default=200)
    parser.add_argument("--workdays-body", default=WORKDAYS)
    parser.add_argument("--delay", type=float, default=0.0)
    parser.add_argument("--delay-route", default="holidays")
    args = parser.parse_args()

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.holidays_status = args.holidays_status
    server.holidays_body = args.holidays_body
    server.workdays_status = args.workdays_status
    server.workdays_body = args.workdays_body
    server.delay = args.delay
    server.delay_route = args.delay_route
    server.log = open(args.log, "a", encoding="utf-8")
    import threading

    server.lock = threading.Lock()
    with open(args.port_file, "w", encoding="utf-8") as port_file:
        port_file.write(str(server.server_address[1]))
    server.serve_forever()


if __name__ == "__main__":
    sys.exit(main())
