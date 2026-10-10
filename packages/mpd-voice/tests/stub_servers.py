"""Tiny threading HTTP stubs for the STT/TTS backend tests."""

from __future__ import annotations

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DEFAULT_STT_BODY = b'{"text": " next track "}'


class _Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self) -> None:  # noqa: N802 - http.server API
        body = json.dumps({"data": [{"id": "stub"}]}).encode()
        self._answer(200, body)

    def do_POST(self) -> None:  # noqa: N802 - http.server API
        length = int(self.headers.get("Content-Length", 0))
        self.server.requests.append(  # type: ignore[attr-defined]
            (
                self.path,
                self.headers.get("Content-Type", ""),
                self.rfile.read(length),
            )
        )
        status, payload = self.server.response  # type: ignore[attr-defined]
        self._answer(status, payload)

    def _answer(self, status: int, payload: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *_args: object) -> None:
        return None


class StubServer:
    """OpenAI-compatible endpoint stub: ``GET /v1/models`` always succeeds."""

    def __init__(
        self, status: int = 200, payload: bytes = DEFAULT_STT_BODY
    ) -> None:
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
        self.server.requests = []  # type: ignore[attr-defined]
        self.server.response = (status, payload)  # type: ignore[attr-defined]
        self.thread = threading.Thread(
            target=self.server.serve_forever, daemon=True
        )
        self.thread.start()

    @property
    def base_url(self) -> str:
        host, port = self.server.server_address[:2]
        return f"http://{host}:{port}"

    @property
    def requests(self) -> list[tuple[str, str, bytes]]:
        return self.server.requests  # type: ignore[attr-defined]

    def stop(self) -> None:
        self.server.shutdown()
        self.server.server_close()
