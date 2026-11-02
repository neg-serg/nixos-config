#!/usr/bin/env python3
"""Local stand-in for the weather providers, used by tests/parity.sh.

It answers the four request paths the worker talks to, logs every request line
(path and User-Agent) as JSON lines, and can be told to fail or to stall so the
parity harness can compare the shell and the Rust port on the same input:

    mock_providers.py --port-file FILE --log FILE [--forecast-status N]
                      [--forecast-body TEXT] [--metno-body TEXT]
                      [--wttr-body TEXT] [--delay SECONDS]

The listener binds 127.0.0.1:0 and writes the chosen port to --port-file, so
the harness never guesses a port. Dev-only tooling: it is not part of the
package build.
"""

import argparse
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

GEOCODE = (
    '{"generationtime_ms":0.5,"results":[{"id":498817,"name":"Saint Petersburg",'
    '"latitude":59.93863,"longitude":30.31413,"country":"Russia",'
    '"admin1":"City of Saint Petersburg","timezone":"Europe/Moscow"}],'
    '"query":{"name":"Saint Petersburg"}}'
)

FORECAST = (
    '{"latitude":59.93863,"longitude":30.31413,"generationtime_ms":0.11,'
    '"utc_offset_seconds":0,"timezone":"GMT","timezone_abbreviation":"GMT",'
    '"elevation":10.0,'
    '"current_units":{"time":"iso8601","interval":"seconds","temperature_2m":"C",'
    '"weather_code":"wmo code","wind_speed_10m":"m/s","wind_direction_10m":"deg",'
    '"is_day":"","relative_humidity_2m":"%","surface_pressure":"hPa"},'
    '"current":{"time":"2026-11-02T12:00","interval":900,"temperature_2m":6.3,'
    '"weather_code":3,"wind_speed_10m":3.40,"wind_direction_10m":231,"is_day":0,'
    '"relative_humidity_2m":81,"surface_pressure":1027.4},'
    '"daily_units":{"time":"iso8601","temperature_2m_max":"C",'
    '"temperature_2m_min":"C","weathercode":"wmo code"},'
    '"daily":{"time":["2026-11-02","2026-11-03"],'
    '"temperature_2m_max":[7.9,7.0],"temperature_2m_min":[5.6,4.0],'
    '"weathercode":[3,53]}}'
)

METNO = (
    '{"type":"Feature","geometry":{"type":"Point",'
    '"coordinates":[30.31413,59.93863,10]},"properties":{"meta":{"updated_at":'
    '"2026-11-02T12:00:00Z","units":{"air_temperature":"celsius"}},"timeseries":['
    '{"time":"2026-11-02T12:00:00Z","data":{"instant":{"details":'
    '{"air_temperature":7.9}},"next_1_hours":{"summary":{"symbol_code":'
    '"partlycloudy_day"},"details":{"precipitation_amount":0.0}}}},'
    '{"time":"2026-11-02T18:00:00Z","data":{"instant":{"details":'
    '{"air_temperature":5.6}},"next_6_hours":{"summary":{"symbol_code":'
    '"rain"}}}},'
    '{"time":"2026-11-03T12:00:00Z","data":{"instant":{"details":'
    '{"air_temperature":7.0}},"next_1_hours":{"summary":{"symbol_code":'
    '"cloudy"}}}}]}}'
)

WTTR = "Partly cloudy|+3°C|81%|↑8km/h|Partly cloudy|1009|29.80|0"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "pleamar-weather-mock"

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

        args = self.server.args
        route = "path"
        if path.startswith("/geo/v1/search"):
            route = "geo"
        elif path.startswith("/v1/forecast"):
            route = "forecast"
        elif path.startswith("/metno/compact"):
            route = "metno"
        elif path.startswith("/wttr/"):
            route = "wttr"
        if args.delay and route in args.delay_routes.split(","):
            time.sleep(args.delay)

        status = 200
        body = "not found\n"
        if route == "geo":
            if args.geocode_status:
                status = args.geocode_status
                body = "upstream error %d\n" % args.geocode_status
            else:
                body = args.geocode_body or GEOCODE
        elif route == "forecast":
            if args.forecast_status:
                status = args.forecast_status
                body = "upstream error %d\n" % args.forecast_status
            else:
                body = args.forecast_body or FORECAST
        elif route == "metno":
            body = args.metno_body or METNO
        elif route == "wttr":
            body = args.wttr_body or WTTR
        else:
            status = 404

        data = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):  # silence the default request log
        pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port-file", required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--geocode-status", type=int, default=0)
    parser.add_argument("--geocode-body", default="")
    parser.add_argument("--forecast-status", type=int, default=0)
    parser.add_argument("--forecast-body", default="")
    parser.add_argument("--metno-body", default="")
    parser.add_argument("--wttr-body", default="")
    parser.add_argument("--delay", type=float, default=0.0)
    parser.add_argument("--delay-routes", default="forecast")
    args = parser.parse_args()

    log = open(args.log, "w", encoding="utf-8")
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.args = args
    server.log = log
    server.lock = threading.Lock()
    port = server.server_address[1]
    with open(args.port_file, "w", encoding="utf-8") as port_file:
        port_file.write(str(port))
        port_file.flush()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        log.close()


if __name__ == "__main__":
    sys.exit(main())
