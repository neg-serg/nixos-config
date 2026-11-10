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

# Chars per token by script, measured on qwen3.8 and devstral and rounded down
# to the pessimistic end. See `char_tokens` for the samples and the reason the
# whole text is priced at the rate of the dominant non-Latin script.
CPK_CJK = 1.2
CPK_CYRILLIC = 2.5
CPK_LATIN = 4.6
CPK_OTHER = 3.2
MIXED_SCRIPT_SHARE = 0.15  # share of CJK/Cyrillic that makes it text-defining
SAFETY = 1.05  # never tighten a request to the exact edge of the slot
PROMPT_OVERHEAD = 4  # per-message template tokens (role markers, separators)

# Backoff between the three attempts at one request. Short enough that a
# healthy swap recovers inside the client's own timeout, long enough for
# llama-swap to finish stopping the previous backend.
RETRY_DELAYS = (5, 10, 15)


def log_line(message):
    """One line per event to stderr, which journald keeps for the unit."""
    print(f"llm-proxy: {message}", file=sys.stderr, flush=True)


def _empty_row():
    return {"requests": 0, "trimmed": 0, "retries": 0, "errors": 0}


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
            if not model:
                return
            row = self.per_model.setdefault(model, _empty_row())
            # Only the counter that was bumped moves: incrementing `requests`
            # on every event made the per-model row useless (a trim or a retry
            # showed up as another request).
            if field in row:
                row[field] += n

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


def char_tokens(text):
    """Tokens for `text`, by character class.

    Measured on qwen3.8 and devstral over the same texts, baseline
    subtracted: English prose runs at 4.7 chars/token, source code at 3.6,
    Russian at 2.9, Russian technical prose (paths, unit names, numbers) at
    2.5, and Chinese at 1.2 on devstral. One constant understates CJK by a
    factor of two — the request then hits the slot limit and fails with the
    400 this guard exists to prevent.

    A mixed text cannot be priced class by class either: `systemd-юнит` and
    `journalctl -u` do not tokenize at English rates when they sit inside
    Russian prose, and doing so understated exactly that case by a third. So
    once a script is a substantial share of the text, the whole text is
    priced at that script's rate — the pessimistic end, which can trim a
    little early but never overflows the slot.
    """
    cjk = cyrillic = latin = other = 0
    for ch in text:
        code = ord(ch)
        if code < 128:
            if ch.isalpha():
                latin += 1
            else:
                other += 1
        elif 0x0400 <= code <= 0x04FF or 0x0370 <= code <= 0x03FF:
            cyrillic += 1
        elif (
            0x3040 <= code <= 0x30FF
            or 0x3400 <= code <= 0x4DBF
            or 0x4E00 <= code <= 0x9FFF
            or 0xAC00 <= code <= 0xD7AF
            or 0xF900 <= code <= 0xFAFF
        ):
            cjk += 1
        elif ch.isalpha():
            latin += 1
        else:
            other += 1
    total = cjk + cyrillic + latin + other
    if total:
        if cjk / total >= MIXED_SCRIPT_SHARE:
            return total / CPK_CJK
        if cyrillic / total >= MIXED_SCRIPT_SHARE:
            return total / CPK_CYRILLIC
    return (
        cjk / CPK_CJK
        + cyrillic / CPK_CYRILLIC
        + latin / CPK_LATIN
        + other / CPK_OTHER
    )


def estimate_tokens(messages, tools=None):
    """Estimate the prompt size. Exact counting would need the chat template,
    which only the server knows; the per-class rates above plus a small margin
    are close enough to keep a request inside the slot."""
    tokens = 0.0
    for m in messages:
        tokens += char_tokens(m.get("content") or "") + PROMPT_OVERHEAD
        for tc in m.get("tool_calls") or []:
            tokens += char_tokens(json.dumps(tc)) + PROMPT_OVERHEAD
    if tools:
        tokens += char_tokens(json.dumps(tools))
    return int(tokens * SAFETY) + 8


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


SINGLE_TOOL_KINDS = ("tool", "command", "function", "action", "call")


def message_texts(message):
    """Text blocks of a message, for a system prompt that may be multimodal."""
    content = message.get("content")
    if isinstance(content, str):
        return [content]
    if isinstance(content, list):
        return [
            part.get("text") or ""
            for part in content
            if isinstance(part, dict)
        ]
    return []


def asks_single_tool(messages):
    """True when the client already asks for one action per turn.

    Clients phrase this themselves — the sysadmin bench sends "Run exactly
    ONE command per turn" — and matching only our exact wording appended a
    second, differently worded copy of the same rule.
    """
    rule = SINGLE_TOOL_RULE.lower()
    for message in messages:
        if message.get("role") != "system":
            continue
        for text in message_texts(message):
            low = " ".join(text.lower().split())
            if rule in low:
                return True
            if "per turn" in low and any(
                f"one {kind} per turn" in low for kind in SINGLE_TOOL_KINDS
            ):
                return True
    return False


def inject_single_tool_rule(messages, enabled):
    """Merge the rule into the client's system prompt when there is one.

    A second system message is not portable: the Mistral/Devstral template
    rejects any `system` role that is not the first message ("Only user,
    assistant and tool roles are supported, got system" -> HTTP 500), so the
    rule has to extend the existing prompt instead of preceding it."""
    if not enabled or asks_single_tool(messages):
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
        text = m["content"]
        # Convert the token budget back to characters with this block's own
        # measured rate: a Russian or CJK dump holds far more tokens per
        # character than English, and a fixed rate would cut it too late.
        per_token = len(text) / max(1.0, char_tokens(text))
        keep_chars = max(400, int((budget - 128) * per_token / SAFETY))
        if len(text) <= keep_chars + len(marker):
            break  # already as short as this path can make it
        half = max(200, keep_chars // 2)
        msg = dict(m)
        msg["content"] = text[:half] + marker + text[-half:]
        for i, x in enumerate(msgs):
            if x is m:
                msgs[i] = msg
                break
        trimmed += over
        # No break: one dump may be the only thing over budget, or several
        # may be; the loop re-measures and cuts again until it fits.

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


class UpstreamError(Exception):
    """An upstream HTTP error whose body was already read for the log.

    The body cannot be re-read from the response afterwards, so it travels
    here and the handler relays it to the client unchanged."""

    def __init__(self, code, detail):
        super().__init__(f"{code}: {detail[:200]}")
        self.code = code
        self.detail = detail


def chat(up, payload, stats, model):
    """POST with the swap-race retry llmctl uses: unload, wait, retry."""
    last = None
    for attempt in range(3):
        try:
            return up.request("/v1/chat/completions", payload)
        except urllib.error.HTTPError as exc:
            detail = exc.read()[:2000].decode(errors="replace")
            # Every attempt is logged, not just the last one: the retries are
            # where a swap race shows its first symptom, and the client usually
            # keeps only the status code.
            log_line(
                f"upstream {exc.code} for {model} "
                f"(attempt {attempt + 1}/3): {detail}"
            )
            last = UpstreamError(exc.code, detail)
            if exc.code < 500:
                raise last from None
            if attempt == len(RETRY_DELAYS) - 1:
                break  # no retry left: count it as a failure, not a retry
            stats.bump("retries", model)
            up.unload()
            up.wait_idle()
            time.sleep(RETRY_DELAYS[attempt])
        except urllib.error.URLError as exc:
            last = exc
            log_line(f"upstream unreachable for {model}: {exc}")
            stats.bump("retries", model)
            time.sleep(RETRY_DELAYS[attempt])
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
        except UpstreamError as exc:
            # Already logged per attempt inside chat(); the client gets the body.
            STATS.bump("errors", requested)
            self._json(exc.code, {"error": {"message": exc.detail}}, headers)
        except urllib.error.HTTPError as exc:
            # The streaming path talks to the upstream directly, so it can
            # still raise here with the body unread.
            STATS.bump("errors", requested)
            detail = exc.read()[:2000].decode(errors="replace")
            log_line(f"upstream {exc.code} for {requested}: {detail}")
            self._json(exc.code, {"error": {"message": detail}}, headers)
        except OSError as exc:
            STATS.bump("errors", requested)
            log_line(f"upstream error for {requested}: {exc}")
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
