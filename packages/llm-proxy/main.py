#!/usr/bin/env python3
"""llm-proxy — context guard and tool-protocol normalizer for llama-swap.

llama-swap already swaps models and speaks the OpenAI API, but it cannot do
three things this fleet needs:

  * keep a request inside the slot's context window (llama-server answers
    400 when the prompt does not fit, and a long agent chain reaches that
    point silently);
  * normalize the tool-calling protocol quirk of small models (they batch
    dependent calls and invent the values they should have read, and they
    expect tool results as plain text with a `name`, not a JSON wrapper);
  * retry the swap race (500 "group starting ... aborted", 502 "proxy
    error: EOF") by unloading and waiting, which is what llmctl does by hand.

Every guard is opt-in per model profile in the JSON config, so the proxy is a
transparent passthrough for anything not listed.

Usage: llm-proxy --config /etc/llm-proxy/config.json
"""

import argparse
import json
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SINGLE_TOOL_RULE = (
    "Call exactly one tool per turn and wait for its result before calling the "
    "next one. Never guess a value that a tool can return."
)

CHARS_PER_TOKEN = 3.6  # English + code mix; trimmed requests get a 10% margin


class Stats:
    def __init__(self):
        self.lock = threading.Lock()
        self.requests = 0
        self.trimmed = 0
        self.retries = 0
        self.errors = 0
        self.per_model = {}

    def bump(self, field, model=None, n=1):
        with self.lock:
            setattr(self, field, getattr(self, field) + n)
            if model:
                row = self.per_model.setdefault(
                    model, {"requests": 0, "trimmed": 0}
                )
                row["requests"] += 1
                if field == "trimmed":
                    row["trimmed"] += n

    def snapshot(self):
        with self.lock:
            return {
                "requests": self.requests,
                "trimmed": self.trimmed,
                "retries": self.retries,
                "errors": self.errors,
                "per_model": self.per_model,
            }


STATS = Stats()


# ---------------------------------------------------------------- config


def load_config(path):
    with open(path) as f:
        cfg = json.load(f)
    cfg.setdefault("upstream", "http://127.0.0.1:9292")
    cfg.setdefault("host", "127.0.0.1")
    cfg.setdefault("port", 9300)
    cfg.setdefault("defaults", {})
    cfg.setdefault("profiles", {})
    base = {
        "ctx": 32768,
        "reserve": 4096,
        "keep_tool_results": 6,
        "keep_last_messages": 8,
        "single_tool": True,
        "thinking": None,
        "target": None,
    }
    cfg["defaults"] = {**base, **cfg["defaults"]}
    return cfg


def profile_for(cfg, model):
    prof = dict(cfg["defaults"])
    prof.update(cfg["profiles"].get(model, {}))
    return prof


# ---------------------------------------------------------------- tokens


def estimate_tokens(messages, tools=None):
    """Cheap estimate with a safety margin. Exact counting would need the chat
    template, which only the server knows; being 10% pessimistic is enough."""
    chars = 0
    for m in messages:
        chars += len(m.get("content") or "") + 12
        for tc in m.get("tool_calls") or []:
            chars += len(json.dumps(tc)) + 12
    if tools:
        chars += len(json.dumps(tools))
    return int(chars / CHARS_PER_TOKEN * 1.1) + 8


# ------------------------------------------------------- tool protocol


def tool_call_names(messages):
    """Map tool_call_id -> function name so a tool result can carry `name`."""
    names = {}
    for m in messages:
        for tc in m.get("tool_calls") or []:
            fn = tc.get("function") or {}
            if tc.get("id") and fn.get("name"):
                names[tc["id"]] = fn["name"]
    return names


def normalize_tool_results(messages):
    """llama.cpp renders a tool message as plain text with an optional `name`.
    A JSON wrapper ({"result": ...}) makes small models misread the value —
    this was measured on the sysadmin bench — so unwrap it here."""
    names = tool_call_names(messages)
    out = []
    for m in messages:
        if m.get("role") != "tool":
            out.append(m)
            continue
        m = dict(m)
        content = m.get("content")
        if isinstance(content, str):
            try:
                parsed = json.loads(content)
            except json.JSONDecodeError:
                parsed = None
            if isinstance(parsed, dict) and set(parsed) == {"result"}:
                content = (
                    json.dumps(parsed["result"])
                    if not isinstance(parsed["result"], str)
                    else parsed["result"]
                )
            m["content"] = content
        if not m.get("name") and m.get("tool_call_id") in names:
            m["name"] = names[m["tool_call_id"]]
        out.append(m)
    return out


def inject_single_tool_rule(messages, enabled):
    """Merge the rule into the client's system prompt when there is one.

    A second system message is not portable: the Mistral/Devstral template
    rejects any `system` role that is not the first message ("Only user,
    assistant and tool roles are supported, got system" -> HTTP 500), so the
    rule has to extend the existing prompt instead of preceding it."""
    if not enabled:
        return messages
    if any(
        m.get("role") == "system"
        and SINGLE_TOOL_RULE in (m.get("content") or "")
        for m in messages
    ):
        return messages
    out = [dict(m) for m in messages]
    for i, m in enumerate(out):
        if m.get("role") != "system":
            continue
        content = m.get("content")
        if isinstance(content, list):
            content = list(content) + [
                {"type": "text", "text": SINGLE_TOOL_RULE}
            ]
        else:
            content = "\n\n".join(p for p in (content, SINGLE_TOOL_RULE) if p)
        out[i] = {**m, "content": content}
        return out
    rule = {"role": "system", "content": SINGLE_TOOL_RULE}
    return [rule] + out


# ---------------------------------------------------------------- trimming


def split_units(messages):
    """Group an assistant tool-call message with the tool results it owns: a
    template breaks if only one half survives."""
    units = []
    i = 0
    while i < len(messages):
        m = messages[i]
        if m.get("role") == "assistant" and m.get("tool_calls"):
            unit = [m]
            j = i + 1
            while j < len(messages) and messages[j].get("role") == "tool":
                unit.append(messages[j])
                j += 1
            units.append({"kind": "tool_call", "msgs": unit})
            i = j
        else:
            units.append({"kind": m.get("role", "user"), "msgs": [m]})
            i += 1
    return units


def fit(messages, budget, keep_tool_results, keep_last_messages, tools=None):
    """Drop the oldest tool-result groups, then the oldest turns, until the
    request fits. The system prompt and the current turn always survive."""
    trimmed = 0
    units = split_units(messages)

    def size():
        flat = [m for u in units for m in u["msgs"]]
        return estimate_tokens(flat, tools)

    def drop(idx):
        nonlocal trimmed
        before = size()
        del units[idx]
        trimmed += max(0, before - size())

    while size() > budget:
        tool_idx = [i for i, u in enumerate(units) if u["kind"] == "tool_call"]
        if len(tool_idx) > keep_tool_results:
            drop(tool_idx[0])
            continue
        # Oldest non-system turn, never the last unit (the current request).
        turn_idx = [
            i
            for i, u in enumerate(units)
            if u["kind"] in ("user", "assistant") and i < len(units) - 1
        ]
        if len(turn_idx) > keep_last_messages:
            drop(turn_idx[0])
            continue
        # Last resort: keep the head and the tail of the largest text block and
        # cut the middle out. The tail carries the current ask, the head carries
        # the framing, so neither is worth dropping for the middle of a dump.
        marker = "\n… [trimmed by llm-proxy] …\n"
        flat = [
            (u["msgs"], m)
            for u in units
            for m in u["msgs"]
            if isinstance(m.get("content"), str)
        ]
        if not flat:
            break
        msgs, m = max(flat, key=lambda p: len(p[1]["content"]))
        over = size() - budget
        budget_chars = max(
            400, int((budget - 128) * CHARS_PER_TOKEN / 1.1) - len(marker)
        )
        half = max(200, budget_chars // 2)
        msg = dict(m)
        msg["content"] = m["content"][:half] + marker + m["content"][-half:]
        for i, x in enumerate(msgs):
            if x is m:
                msgs[i] = msg
                break
        trimmed += over
        break

    return [m for u in units for m in u["msgs"]], trimmed


# ---------------------------------------------------------------- upstream


class Upstream:
    def __init__(self, base):
        self.base = base.rstrip("/")

    def request(self, path, body=None, timeout=900):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(
            self.base + path,
            data=data,
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read(), dict(r.headers)

    def raw(self, path, body, timeout=900):
        data = json.dumps(body).encode()
        req = urllib.request.Request(
            self.base + path,
            data=data,
            headers={"Content-Type": "application/json"},
        )
        return urllib.request.urlopen(req, timeout=timeout)

    def unload(self):
        try:
            self.request("/unload", timeout=15)
        except OSError:
            pass

    def running(self):
        try:
            body, _ = self.request("/running", timeout=5)
            return json.loads(body).get("running") or []
        except OSError:
            return []

    def wait_idle(self, deadline_s=60):
        end = time.time() + deadline_s
        while time.time() < end and self.running():
            time.sleep(1)


def chat(up, payload, stats, model):
    """POST with the swap-race retry llmctl uses: unload, wait, retry."""
    last = None
    for attempt in range(3):
        try:
            return up.request("/v1/chat/completions", payload)
        except urllib.error.HTTPError as exc:
            last = exc
            if exc.code < 500:
                raise
            stats.bump("retries", model)
            up.unload()
            up.wait_idle()
            time.sleep(5 * (attempt + 1))
        except urllib.error.URLError as exc:
            last = exc
            stats.bump("retries", model)
            time.sleep(5 * (attempt + 1))
    raise last


# ---------------------------------------------------------------- handler


class Handler(BaseHTTPRequestHandler):
    cfg = None
    up = None
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):  # keep journald quiet per request
        pass

    def _json(self, code, obj, extra_headers=None):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra_headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            return self._json(200, {"status": "ok"})
        if self.path == "/stats":
            return self._json(200, STATS.snapshot())
        if self.path in ("/v1/models", "/models"):
            try:
                body, _ = self.up.request("/v1/models", timeout=15)
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            except OSError as exc:
                self._json(502, {"error": {"message": str(exc)}})
            return
        self._json(404, {"error": {"message": "not found"}})

    def do_POST(self):
        if self.path not in ("/v1/chat/completions", "/chat/completions"):
            return self._json(404, {"error": {"message": "not found"}})
        length = int(self.headers.get("Content-Length") or 0)
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError as exc:
            return self._json(400, {"error": {"message": f"bad json: {exc}"}})

        requested = payload.get("model") or ""
        model = requested
        prof = profile_for(self.cfg, requested)
        STATS.bump("requests", requested)

        if prof.get("target"):
            payload["model"] = prof["target"]
            model = prof["target"]
        if prof.get("thinking") is False:
            kwargs = payload.setdefault("chat_template_kwargs", {})
            kwargs.setdefault("enable_thinking", False)

        messages = payload.get("messages") or []
        messages = normalize_tool_results(messages)
        tools = payload.get("tools")
        messages = inject_single_tool_rule(
            messages, prof.get("single_tool") and tools
        )

        budget = int(prof["ctx"]) - int(prof["reserve"])
        if estimate_tokens(messages, tools) > budget:
            messages, trimmed = fit(
                messages,
                budget,
                int(prof["keep_tool_results"]),
                int(prof["keep_last_messages"]),
                tools,
            )
            if trimmed:
                STATS.bump("trimmed", requested)

        payload["messages"] = messages
        prompt_tokens = estimate_tokens(messages, tools)
        if payload.get("max_tokens"):
            payload["max_tokens"] = min(
                int(payload["max_tokens"]),
                max(64, int(prof["ctx"]) - prompt_tokens - 64),
            )

        headers = {
            "x-llm-proxy-model": model,
            "x-llm-proxy-prompt-tokens": str(prompt_tokens),
            "x-llm-proxy-ctx": str(prof["ctx"]),
        }
        try:
            if payload.get("stream"):
                resp = self.up.raw("/v1/chat/completions", payload)
                self.send_response(resp.status)
                for k, v in resp.headers.items():
                    if k.lower() in ("content-type", "cache-control"):
                        self.send_header(k, v)
                self.send_header("Transfer-Encoding", "chunked")
                for k, v in headers.items():
                    self.send_header(k, v)
                self.end_headers()
                while True:
                    chunk = resp.read(8192)
                    if not chunk:
                        break
                    self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk))
                self.wfile.write(b"0\r\n\r\n")
                return
            body, _ = chat(self.up, payload, STATS, requested)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            for k, v in headers.items():
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(body)
        except urllib.error.HTTPError as exc:
            STATS.bump("errors", requested)
            detail = exc.read()[:2000].decode(errors="replace")
            # The client may drop the body (the bench runner only keeps the
            # status), and llama-swap logs just "non-200 response", so the
            # reason would otherwise vanish: keep it in the journal.
            print(
                f"upstream {exc.code} for {requested}: {detail}",
                file=sys.stderr,
                flush=True,
            )
            self._json(exc.code, {"error": {"message": detail}}, headers)
        except OSError as exc:
            STATS.bump("errors", requested)
            print(
                f"upstream error for {requested}: {exc}",
                file=sys.stderr,
                flush=True,
            )
            self._json(502, {"error": {"message": str(exc)}}, headers)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="/etc/llm-proxy/config.json")
    args = ap.parse_args()
    cfg = load_config(args.config)
    Handler.cfg = cfg
    Handler.up = Upstream(cfg["upstream"])
    srv = ThreadingHTTPServer((cfg["host"], int(cfg["port"])), Handler)
    print(
        f"llm-proxy listening on {cfg['host']}:{cfg['port']} -> {cfg['upstream']}",
        flush=True,
    )
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
