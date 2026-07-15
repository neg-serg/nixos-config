#!/usr/bin/env python3
"""zen-cookie-cdp-write: Write decrypted cookies to Vivaldi using Chrome DevTools Protocol.

Uses Vivaldi's own CDP endpoint to set cookies, avoiding direct SQLite manipulation
and Vivaldi's internal OSCrypt encryption. Vivaldi handles all encryption internally
when cookies are set via Network.setCookie.

Usage:
    python3 zen-cookie-cdp-write.py --profile /path/to/vivaldi/Default

Reads a JSON array of cookie objects from stdin (output of zen-cookie-decrypt).
"""

import argparse
import json
import os
import signal
import socket
import subprocess
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

from websocket import create_connection, WebSocket


# ── Helpers ──────────────────────────────────────────────────────────────────


def find_free_port() -> int:
    """Find a free TCP port on localhost."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def wait_for_port(port: int, timeout: float = 15.0) -> bool:
    """Wait until a TCP port is accepting connections."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=1):
                return True
        except (OSError, ConnectionRefusedError):
            time.sleep(0.3)
    return False


def http_get_json(port: int, path: str):
    """Fetch JSON from a CDP HTTP endpoint."""
    resp = urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=5)
    return json.loads(resp.read().decode("utf-8"))


def get_page_ws(port: int) -> tuple[WebSocket, str]:
    """Find or create a page target and connect to its WebSocket directly.

    Returns (page_ws, target_id). Network.setCookie requires a Page-level
    CDP session so we connect directly to the page target's WS URL.
    """
    pages = http_get_json(port, "/json")

    # Filter to page-type targets with WS URLs
    pages = [
        p
        for p in pages
        if p.get("type") == "page" and p.get("webSocketDebuggerUrl")
    ]

    if not pages:
        # Try creating one via HTTP endpoint
        print("  No pages found, creating via /json/new...", file=sys.stderr)
        try:
            new_page = http_get_json(port, "/json/new?url=https://google.com")
            pages = [new_page] if isinstance(new_page, dict) else new_page
            pages = [p for p in pages if p.get("webSocketDebuggerUrl")]
        except Exception as exc:
            print(f"  /json/new failed: {exc}", file=sys.stderr)
            sys.exit(3)

    if not pages:
        print("Error: Could not find or create a page target", file=sys.stderr)
        sys.exit(3)

    target = pages[0]
    target_id = target.get("id", "?")
    ws_url = target["webSocketDebuggerUrl"]

    print(
        f"  Using page target: {target_id[:8] if target_id != '?' else '?'}...",
        file=sys.stderr,
    )
    print(f"  Connecting to page WS: {ws_url[:60]}...", file=sys.stderr)

    page_ws = create_connection(ws_url, timeout=15)
    page_ws.settimeout(30)
    # Small delay for page to initialize
    time.sleep(0.3)

    return page_ws, target_id


# ── Vivaldi lifecycle ────────────────────────────────────────────────────────


def start_vivaldi(port: int, profile_dir: str) -> subprocess.Popen:
    """Start Vivaldi with CDP enabled via xvfb (virtual display).

    Uses ``xvfb-run`` to provide a virtual display so Vivaldi runs in
    non-headless mode, which ensures proper cookie persistence to SQLite.

    ``profile_dir`` should be the Vivaldi user data directory
    (parent of the ``Default`` profile, e.g. ``~/.config/vivaldi/``),
    NOT the ``Default`` directory itself.

    Returns the Popen handle so the caller can terminate it.
    """
    # If profile_dir ends with /Default, use its parent as user-data-dir
    user_data_dir = profile_dir
    profile_name = ""
    if profile_dir.rstrip("/").endswith("/Default"):
        user_data_dir = os.path.dirname(profile_dir.rstrip("/"))
        profile_name = "Default"

    cmd = [
        "xvfb-run",
        "--auto-servernum",
        "vivaldi",
        f"--remote-debugging-port={port}",
        "--remote-allow-origins=*",
        "--no-first-run",
        "--no-sandbox",
        "--disable-dev-shm-usage",
        f"--user-data-dir={user_data_dir}",
    ]
    if profile_name:
        cmd.append(f"--profile-directory={profile_name}")
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        preexec_fn=lambda: os.setpgrp(),
    )
    return proc


def stop_vivaldi(proc: subprocess.Popen) -> None:
    """Terminate Vivaldi gracefully, with fallback to kill."""
    if proc.poll() is not None:
        return

    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass

    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
        proc.wait(timeout=5)


# ── CDP cookie setting ───────────────────────────────────────────────────────


def send_cmd(
    ws: WebSocket, method: str, params: dict | None = None, msg_id: int = 1
) -> dict:
    """Send a raw CDP command and wait for matching response by ID.

    Discards any event messages that arrive between sending and response.
    """
    cmd: dict = {"id": msg_id, "method": method}
    if params:
        cmd["params"] = params
    ws.send(json.dumps(cmd))
    while True:
        raw = ws.recv()
        resp = json.loads(raw)
        if resp.get("id") == msg_id:
            return resp


def enable_network(ws: WebSocket) -> None:
    """Enable the Network domain so we can call Network methods."""
    resp = send_cmd(ws, "Network.enable", msg_id=1)
    if "error" in resp:
        print(
            f"Warning: Network.enable error: {resp['error']}", file=sys.stderr
        )


def set_cookie_via_cdp(ws: WebSocket, cookie: dict, msg_id: int) -> dict:
    """Set a single cookie via CDP Network.setCookie.

    Returns the CDP response dict.
    """
    host = cookie.get("host", "")
    name = cookie.get("name", "")
    value = cookie.get("value", "")
    path = cookie.get("path", "/")
    expiry = cookie.get("expiry", 0)

    clean_host = host.lstrip(".")
    url = f"https://{clean_host}{path}"

    params: dict = {
        "url": url,
        "name": name,
        "value": value,
        "domain": host,
        "path": path,
        "secure": bool(cookie.get("isSecure", 0)),
        "httpOnly": bool(cookie.get("isHttpOnly", 0)),
    }

    same_site = cookie.get("sameSite", 0)
    if same_site == 1:
        params["sameSite"] = "Lax"
    elif same_site == 2:
        params["sameSite"] = "Strict"
    elif same_site == 0 and cookie.get("isSecure", 0):
        params["sameSite"] = "None"

    if expiry > 0:
        params["expires"] = expiry

    return send_cmd(ws, "Network.setCookie", params, msg_id)


# ── Main ─────────────────────────────────────────────────────────────────────


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Write decrypted cookies to Vivaldi using Chrome DevTools Protocol. "
            "Reads a JSON array from stdin (output of zen-cookie-decrypt), "
            "starts Vivaldi via xvfb with CDP enabled, sets each cookie, "
            "navigates to google.com to trigger persistence, then shuts down."
        ),
    )
    parser.add_argument(
        "--profile",
        required=True,
        help=(
            "Path to a Vivaldi profile directory "
            "(e.g. ~/.config/vivaldi/Default/)"
        ),
    )
    parser.add_argument(
        "--debug-port",
        type=int,
        default=0,
        help="CDP debug port (default: auto-select a free port)",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=30,
        help="Max seconds to wait for Vivaldi startup (default: 30)",
    )
    args = parser.parse_args()

    port = args.debug_port if args.debug_port > 0 else find_free_port()
    profile_dir = os.path.abspath(args.profile)

    # ── Read cookies from stdin ───────────────────────────────────────────────
    raw = sys.stdin.read()
    if not raw.strip():
        print("Error: No input received on stdin", file=sys.stderr)
        sys.exit(1)

    try:
        cookies: list[dict] = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"Error: Invalid JSON on stdin — {exc}", file=sys.stderr)
        sys.exit(1)

    if not isinstance(cookies, list):
        print("Error: Expected a JSON array on stdin", file=sys.stderr)
        sys.exit(1)

    total = len(cookies)
    if total == 0:
        print("No cookies to write.")
        return

    print(
        f"Starting Vivaldi in CDP mode via xvfb (port {port})...",
        file=sys.stderr,
    )

    # ── Start Vivaldi ─────────────────────────────────────────────────────────
    vivaldi_proc = start_vivaldi(port, profile_dir)

    try:
        if not wait_for_port(port, timeout=args.timeout):
            print(
                "Error: Vivaldi did not start within the timeout period",
                file=sys.stderr,
            )
            sys.exit(2)

        # Connect to a page target's WS directly
        ws, target_id = get_page_ws(port)

        # Enable Network domain
        enable_network(ws)

        # ── Set cookies ───────────────────────────────────────────────────────
        print(f"Setting {total} cookies via CDP...", file=sys.stderr)

        success = 0
        failed = 0
        msg_id = 2  # Continue from id 1 (Network.enable)

        for i, cookie in enumerate(cookies):
            try:
                resp = set_cookie_via_cdp(ws, cookie, msg_id)
                msg_id += 1

                if "error" not in resp and resp.get("result", {}).get(
                    "success"
                ):
                    success += 1
                else:
                    failed += 1
                    err_msg = resp.get("error", {}).get("message", "unknown")
                    if failed <= 5:
                        name = cookie.get("name", "?")
                        host = cookie.get("host", "?")
                        print(
                            f"  Failed: {name} @ {host} — {err_msg}",
                            file=sys.stderr,
                        )
            except Exception as exc:
                failed += 1
                if failed <= 5:
                    print(
                        f"  Error setting cookie '{cookie.get('name', '?')}': "
                        f"{exc}",
                        file=sys.stderr,
                    )

            if (i + 1) % 500 == 0 or (i + 1) == total:
                pct = (i + 1) / total * 100
                print(
                    f"  {i+1}/{total} ({pct:.0f}%) — {success} OK, "
                    f"{failed} failed",
                    file=sys.stderr,
                )

        print(
            f"Done: {success}/{total} cookies set successfully",
            file=sys.stderr,
        )
        if failed > 0:
            print(f"  {failed} cookies failed", file=sys.stderr)

        # ── Persist cookies to disk ───────────────────────────────────────────
        if success > 0:
            print("  Flushing cookies...", file=sys.stderr)
            # Navigate to trigger cookie store flush
            send_cmd(
                ws, "Page.navigate", {"url": "about:blank"}, msg_id=msg_id
            )
            # Wait generously for async cookie store writes to complete
            time.sleep(10.0)

        # Close the WS connection
        ws.close()

        # Try graceful Vivaldi shutdown via HTTP (browser close)
        # This triggers proper cookie store finalization.
        try:
            urllib.request.urlopen(
                f"http://127.0.0.1:{port}/json/close",
                timeout=5,
            )
        except Exception:
            pass
        # Give Vivaldi time to flush before we kill it
        time.sleep(2.0)

    finally:
        # ── Stop Vivaldi ──────────────────────────────────────────────────────
        print("Stopping Vivaldi...", file=sys.stderr)
        stop_vivaldi(vivaldi_proc)
        print("Done.", file=sys.stderr)


if __name__ == "__main__":
    main()
