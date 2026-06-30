#!/usr/bin/env python3
"""pretty.py — unified terminal aesthetics for all Python scripts.

Usage:
    from scripts.lib.pretty import pretty
    pretty.header("Deploying system_description")
    pretty.ok("All 65 states valid")
    pretty.fail("zapret2.sls: missing dependency")
    pretty.warn("gopass locked")
    pretty.info("Log: logs/system_description.log")
    pretty.phase("Installing packages", n=3, total=10)
    pretty.progress(67, 100)
    pretty.section("Network Configuration")
    pretty.summary_line(727, 2, "States")
    pretty.service_status("ollama", "active")
    pretty.status_badge("OK")
    pretty.table(["ID", "Duration", "Result"], [["foo", "12ms", "✓"], ["bar", "340ms", "✗"]])
    pretty.key_value({"Host": "mirage", "OS": "CachyOS", "Kernel": "6.14"})
    pretty.panel("Important context block", title="Details")
    pretty.filepath("~/src/cfg/states/desktop.sls")
    pretty.filesize(1048576)
    pretty.filelen(1423)
    pretty.rule("Dependencies")
    pretty.elapsed(94.3)
    pretty.list_items(["item one", "item two", "item three"])
    pretty.tree(states, key_fn=lambda s: s.name, child_fn=lambda s: s.includes)

    with pretty.spinner("Pulling image"):
        ...slow work...

    out, rc = pretty.capture("salt_contracts.py", ["python3", "scripts/salt_contracts.py"])
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import time
from contextlib import contextmanager
from typing import Callable

# ── Capability detection ──────────────────────────────────────────────────
_IS_TTY = sys.stdout.isatty() and not os.environ.get("NO_COLOR")
_HAS_UTF8 = any(
    enc in (os.environ.get(k, "") or "")
    for enc in ("UTF-8", "utf-8", "utf8")
    for k in ("LANG", "LC_ALL", "LC_CTYPE")
)
_HAS_256 = _IS_TTY and os.environ.get("TERM", "") in (
    "xterm-256color",
    "screen-256color",
    "tmux-256color",
    "foot",
    "alacritty",
    "kitty",
    "wezterm",
)

# ── Color palette ─────────────────────────────────────────────────────────
if _IS_TTY:
    C: dict[str, str] = {
        "reset": "\033[0m",
        "bold": "\033[1m",
        "dim": "\033[2m",
        "italic": "\033[3m",
        "red": "\033[31m",
        "green": "\033[32m",
        "yellow": "\033[33m",
        "blue": "\033[34m",
        "magenta": "\033[35m",
        "cyan": "\033[36m",
        "white": "\033[37m",
        "grey": "\033[90m",
        "red_b": "\033[1;31m",
        "green_b": "\033[1;32m",
        "yellow_b": "\033[1;33m",
        "blue_b": "\033[1;34m",
        "cyan_b": "\033[1;36m",
        "magenta_b": "\033[1;35m",
        "white_b": "\033[1;37m",
        "grey_b": "\033[1;90m",
        # Background colors for badges
        "bg_red": "\033[41m",
        "bg_green": "\033[42m",
        "bg_yellow": "\033[43m",
        "bg_blue": "\033[44m",
        "bg_magenta": "\033[45m",
        "bg_cyan": "\033[46m",
        "bg_grey": "\033[100m",
        "black": "\033[30m",
    }
    if _HAS_256:
        C.update(
            {
                "darkblue": "\033[38;5;24m",
                "nicecyan": "\033[38;5;37m",
                "almostgrey": "\033[38;5;243m",
                "darkgrey": "\033[38;5;238m",
                "subtleyellow": "\033[38;5;220m",
                "softgreen": "\033[38;5;71m",
            }
        )
    else:
        C.update(
            {
                "darkblue": "\033[34m",
                "nicecyan": "\033[36m",
                "almostgrey": "\033[37m",
                "darkgrey": "\033[90m",
                "subtleyellow": "\033[33m",
                "softgreen": "\033[32m",
            }
        )
else:
    _empty_colors = [
        "reset",
        "bold",
        "dim",
        "italic",
        "red",
        "green",
        "yellow",
        "blue",
        "magenta",
        "cyan",
        "white",
        "grey",
        "red_b",
        "green_b",
        "yellow_b",
        "blue_b",
        "cyan_b",
        "magenta_b",
        "white_b",
        "grey_b",
        "bg_red",
        "bg_green",
        "bg_yellow",
        "bg_blue",
        "bg_magenta",
        "bg_cyan",
        "bg_grey",
        "black",
        "darkblue",
        "nicecyan",
        "almostgrey",
        "darkgrey",
        "subtleyellow",
        "softgreen",
    ]
    C = {k: "" for k in _empty_colors}

# ── Icons ─────────────────────────────────────────────────────────────────
if _HAS_UTF8:
    I: dict[str, str] = {  # noqa: E741
        "ok": "✓",
        "fail": "✗",
        "warn": "⚠",
        "info": "●",
        "phase": "▶",
        "clock": "⏳",
        "arrow": "→",
        "star": "★",
        "bullet": "•",
        "box_v": "║",
        "box_h": "═",
        "box_tl": "╔",
        "box_tr": "╗",
        "box_bl": "╚",
        "box_br": "╝",
        "section": "─",
        "branch": "├──",
        "last": "└──",
        "pipe": "│  ",
        "spacer": "   ",
        "ellipsis": "…",
    }
else:
    I = {  # noqa: E741
        "ok": "OK",
        "fail": "!!",
        "warn": "*",
        "info": ">",
        "phase": ">>",
        "clock": "...",
        "arrow": "->",
        "star": "*",
        "bullet": "-",
        "box_v": "|",
        "box_h": "=",
        "box_tl": "+",
        "box_tr": "+",
        "box_bl": "+",
        "box_br": "+",
        "section": "-",
        "branch": "+--",
        "last": "+--",
        "pipe": "|  ",
        "spacer": "   ",
        "ellipsis": "...",
    }

_SPINNER = (
    ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"] if _HAS_UTF8 else ["/", "-", "\\", "|"]
)


def _width():
    try:
        return shutil.get_terminal_size().columns
    except Exception:
        return 80


def _repeat(char: str, count: int) -> str:
    return char * max(count, 0)


def _visible_len(text: str) -> int:
    """Return display width of text, stripping ANSI escape sequences."""
    return len(re.sub(r"\033\[[0-9;]*m", "", text))


def _pad_right(text: str, width: int) -> str:
    """Pad text to visible width, accounting for ANSI codes."""
    vlen = _visible_len(text)
    return text + " " * max(0, width - vlen)


def _pad_left(text: str, width: int) -> str:
    vlen = _visible_len(text)
    return " " * max(0, width - vlen) + text


def _truncate(text: str, width: int, suffix: str = "…") -> str:
    """Truncate text to visible width, appending suffix if needed."""
    if _visible_len(text) <= width:
        return text
    suffix_w = _visible_len(suffix)
    if suffix_w >= width:
        return suffix[:width]
    # Walk characters to find cut point (unaware of ANSI codes, strip them first)
    plain = re.sub(r"\033\[[0-9;]*m", "", text)
    return plain[: width - suffix_w] + suffix


class _Pretty:
    """Singleton pretty printer — all methods are static/instance-agnostic."""

    # ── Core status lines ─────────────────────────────────────────────────

    def header(self, text: str):
        w = _width()
        inner = w - 4
        pad_left = max((inner - _visible_len(text)) // 2, 0)
        pad_right = max(inner - _visible_len(text) - pad_left, 0)
        print(f"{C['magenta_b']}{I['box_tl']}{C['cyan_b']}{_repeat(I['box_h'], w - 2)}{C['magenta_b']}{I['box_tr']}{C['reset']}")
        print(
            f"{C['cyan_b']}{I['box_v']}{C['reset']}{' ' * pad_left}"
            f"{C['white_b']}{text}{C['reset']}{' ' * pad_right} "
            f"{C['cyan_b']}{I['box_v']}{C['reset']}"
        )
        print(f"{C['cyan_b']}{I['box_bl']}{C['magenta_b']}{_repeat(I['box_h'], w - 2)}{C['magenta_b']}{I['box_br']}{C['reset']}")

    def ok(self, text: str):
        print(f"{C['green_b']} {I['ok']} {C['green']}{text}{C['reset']}")

    def fail(self, text: str):
        print(f"{C['red_b']} {I['fail']} {C['red']}{text}{C['reset']}")

    def warn(self, text: str):
        print(f"{C['yellow_b']} {I['warn']} {C['yellow']}{text}{C['reset']}")

    def info(self, text: str):
        print(f"{C['cyan_b']} {I['info']} {C['reset']}{text}{C['reset']}")

    def phase(self, text: str, n: int | None = None, total: int | None = None):
        if n is not None and total is not None:
            print(f"{C['cyan_b']} {I['phase']} {C['subtleyellow']}[{n}/{total}]{C['cyan_b']} {text}{C['reset']}")
        else:
            print(f"{C['cyan_b']} {I['phase']} {text}{C['reset']}")

    def section(self, text: str):
        w = _width()
        remain = max(w - _visible_len(text) - 6, 2)
        print(
            f"{C['grey_b']}{_repeat(I['section'], 3)} {C['cyan_b']}{text} "
            f"{C['grey_b']}{_repeat(I['section'], remain)}{C['reset']}"
        )

    def progress(self, current: int, total: int):
        bar_w = 30
        pct = current * 100 // max(total, 1)
        filled = bar_w * current // max(total, 1)
        empty = bar_w - filled
        bar = f"{C['green']}{_repeat('█', filled)}{C['grey']}{_repeat('░', empty)}"
        print(f"\r{bar} {C['white_b']}{pct:3d}%{C['reset']}  ({current}/{total})", end="")

    def summary_line(self, passed: int, failed: int, label: str = "Results"):
        w = _width()
        passed_s = f"{C['green_b']}{passed} passed"
        if failed:
            text = f"{label}: {passed_s}{C['bold']}, {C['red_b']}{failed} failed"
        else:
            text = f"{label}: {passed_s}"
        plain = re.sub(r"\033\[[0-9;]*m", "", text)
        pad = max((w - len(plain) - 2) // 2, 0)
        print(
            f"{C['bold']}{_repeat(I['section'], pad)} {text} "
            f"{C['bold']}{_repeat(I['section'], pad)}{C['reset']}"
        )

    def service_status(self, name: str, status: str):
        if status in ("active", "running", "healthy", "enabled"):
            print(
                f"{C['green_b']} {I['ok']} {C['green']}{name:<40}"
                f"{C['reset']} {C['green']}active{C['reset']}"
            )
        elif status in ("failed", "error", "unhealthy", "inactive"):
            print(
                f"{C['red_b']} {I['fail']} {C['red']}{name:<40}"
                f"{C['reset']} {C['red']}failed{C['reset']}"
            )
        else:
            print(f"{C['yellow']} {I['warn']} {C['reset']}{name:<40}{C['reset']} {status}")

    # ── Badges ────────────────────────────────────────────────────────────

    def status_badge(self, status: str) -> str:
        """Return a colored inline badge. Use as part of a larger string."""
        s = str(status).upper()
        if s in ("OK", "PASS", "SUCCESS", "ACTIVE", "ENABLED"):
            return f"{C['bg_green']} {C['white_b']}{s}{C['reset']} "
        elif s in ("FAIL", "ERROR", "FAILED", "INACTIVE"):
            return f"{C['bg_red']} {C['white_b']}{s}{C['reset']} "
        elif s in ("WARN", "SKIP", "SKIPPED", "PENDING"):
            return f"{C['bg_yellow']} {C['black']}{s}{C['reset']} "
        elif s in ("CHANGED", "MODIFIED", "UPDATED"):
            return f"{C['bg_cyan']} {C['black']}{s}{C['reset']} "
        elif s in ("INFO", "NOTE"):
            return f"{C['bg_blue']} {C['white_b']}{s}{C['reset']} "
        else:
            return f"{C['bg_grey']} {C['white_b']}{s}{C['reset']} "

    # ── Table ─────────────────────────────────────────────────────────────

    def table(self, headers: list[str], rows: list[list[str]], aligns: list[str] | None = None):
        """Print an aligned table with colored headers.

        aligns: list of '<' (left), '>' (right), '^' (center) per column.
        """
        all_rows = [headers] + rows
        n_cols = max((len(r) for r in all_rows), default=0)
        col_w = [0] * n_cols
        for row in all_rows:
            for i, cell in enumerate(row[:n_cols]):
                col_w[i] = max(col_w[i], _visible_len(str(cell)))

        if aligns is None:
            aligns = ["<"] * n_cols

        def _fmt_cell(cell: str, ci: int) -> str:
            al = aligns[ci] if ci < len(aligns) else "<"
            s = str(cell)
            if al == ">":
                return _pad_left(s, col_w[ci])
            elif al == "^":
                remaining = col_w[ci] - _visible_len(s)
                return " " * (remaining // 2) + s + " " * ((remaining + 1) // 2)
            return _pad_right(s, col_w[ci])

        # Header
        header_line = "  ".join(
            f"{C['white_b']}{_fmt_cell(h, i)}{C['reset']}" for i, h in enumerate(headers[:n_cols])
        )
        print(header_line)
        # Separator
        sep_line = "  ".join(
            f"{C['dim']}{_repeat('─', col_w[i])}{C['reset']}" for i in range(n_cols)
        )
        print(sep_line)
        # Rows
        for row in rows:
            line = "  ".join(
                _fmt_cell(str(row[i]) if i < len(row) else "", i) for i in range(n_cols)
            )
            print(line)

    # ── Key-value pairs ───────────────────────────────────────────────────

    def key_value(self, pairs: dict[str, str] | list[tuple[str, str]], indent: int = 2):
        """Print aligned key: value pairs."""
        items = list(pairs.items()) if isinstance(pairs, dict) else pairs
        if not items:
            return
        max_k = max(_visible_len(k) for k, _ in items)
        prefix = " " * indent
        for k, v in items:
            print(
                f"{prefix}{C['almostgrey']}{_pad_right(k, max_k)} "
                f"{C['dim']}:{C['reset']} {C['white_b']}{v}{C['reset']}"
            )

    # ── Panel (boxed info block) ──────────────────────────────────────────

    def panel(self, text: str, title: str = ""):
        """Print text inside a box-drawn frame, optionally with a title."""
        lines = text.splitlines()
        w = _width()
        max_line = max(_visible_len(line) for line in lines)
        box_w = min(max(max_line, _visible_len(title) + 4) + 4, w - 2)
        box_w = max(box_w, 20)

        top_sep = f"{I['box_tl']}{_repeat(I['box_h'], box_w)}"
        if title:
            top_sep += f" {C['white_b']}{title}{C['reset']}"
        print(f"{C['darkgrey']}{top_sep}{C['reset']}")

        for line in lines:
            padding = " " * max(0, box_w - _visible_len(line) - 1)
            print(
                f"{C['darkgrey']}{I['box_v']}{C['reset']} {line}{padding} "
                f"{C['darkgrey']}{I['box_v']}{C['reset']}"
            )

        print(f"{C['darkgrey']}{I['box_bl']}{_repeat(I['box_h'], box_w)}{I['box_br']}{C['reset']}")

    # ── Rule (horizontal divider with optional title) ─────────────────────

    def rule(self, title: str = ""):
        """Print a horizontal rule, optionally with a centered title."""
        w = _width()
        if title:
            padding = 2
            side = max((w - _visible_len(title) - padding * 2) // 2, 0)
            print(
                f"{C['dim']}{_repeat(I['section'], side)} {C['white_b']}{title}"
                f"{C['reset']} {C['dim']}{_repeat(I['section'], side)}{C['reset']}"
            )
        else:
            print(f"{C['dim']}{_repeat(I['section'], w)}{C['reset']}")

    # ── File path formatting (neg-pretty-printer style) ───────────────────

    def filepath(self, path: str, home: str | None = None) -> str:
        """Colorize a file path: ~ green, / blue, filename bold white."""
        if home is None:
            home = os.environ.get("HOME", os.path.expanduser("~"))
        s = path
        s = s.replace(home, f"{C['green']}~{C['white']}")
        s = re.sub(r"([/·])", f"{C['blue_b']}\\1{C['white']}", s)
        # Resolution markers like -[1920x1080]-
        s = re.sub(
            r"(-\[)([0-9]+)(x)([0-9A-Z]+)(\]-)",
            f"{C['blue']}\\1{C['white']}\\2{C['cyan']}\\3{C['white']}\\4{C['blue']}\\5{C['white']}",
            s,
        )
        return s

    def filesize(self, size: int | float, unit: str | None = None) -> str:
        """Format a file size. Returns a styled string."""
        if unit is None:
            if isinstance(size, (int, float)) and size >= 1024 * 1024 * 1024:
                val, u = size / (1024 * 1024 * 1024), "GB"
            elif isinstance(size, (int, float)) and size >= 1024 * 1024:
                val, u = size / (1024 * 1024), "MB"
            elif isinstance(size, (int, float)) and size >= 1024:
                val, u = size / 1024, "KB"
            else:
                val, u = float(size), "B"
            return f"{C['white_b']}{val:.1f}{C['reset']} {C['dim']}{u}{C['reset']}"
        return f"{C['white_b']}{size}{C['reset']} {C['dim']}{unit}{C['reset']}"

    def filelen(self, count: int | str) -> str:
        """Format a line count. Returns a styled string."""
        return f"{C['almostgrey']}len={C['reset']}{C['white_b']}{count}{C['reset']}"

    # ── Tree ──────────────────────────────────────────────────────────────

    def tree(
        self,
        nodes: list,
        key_fn: Callable[[object], str] = str,
        child_fn: Callable[[object], list] = lambda _: [],
        max_depth: int = 10,
    ):
        """Print a hierarchical tree.

        nodes: list of root objects
        key_fn: extracts display string from a node
        child_fn: extracts list of child nodes from a node
        max_depth: maximum recursion depth
        """

        def _walk(items: list, prefix: str, depth: int):
            if depth > max_depth:
                return
            for i, item in enumerate(items):
                is_last = i == len(items) - 1
                connector = I["last"] if is_last else I["branch"]
                continuation = "    " if is_last else I["pipe"]
                key = key_fn(item)
                print(
                    f"{prefix}{C['darkgrey']}{connector}{C['reset']} {C['white']}{key}{C['reset']}"
                )
                children = child_fn(item)
                if children:
                    _walk(children, prefix + continuation, depth + 1)

        for node in nodes:
            key = key_fn(node)
            print(f"{C['white_b']}{key}{C['reset']}")
            children = child_fn(node)
            if children:
                _walk(children, "", 1)

    # ── List items ────────────────────────────────────────────────────────

    def list_items(self, items: list[str], style: str = "bullet"):
        """Print a bulleted list."""
        bullets = {
            "bullet": I["bullet"],
            "dash": "-",
            "arrow": I["arrow"],
            "star": I["star"],
        }
        bullet = bullets.get(style, I["bullet"])
        for item in items:
            print(f"  {C['dim']}{bullet}{C['reset']} {item}")

    # ── Duration formatting ───────────────────────────────────────────────

    def elapsed(self, seconds: float) -> str:
        """Human-readable elapsed time. Returns a styled string."""
        if seconds < 1:
            return f"{C['white_b']}{int(seconds * 1000)}{C['reset']}{C['dim']}ms{C['reset']}"
        elif seconds < 60:
            return f"{C['white_b']}{seconds:.1f}{C['reset']}{C['dim']}s{C['reset']}"
        elif seconds < 3600:
            m, s = divmod(int(seconds), 60)
            return f"{C['white_b']}{m}m{s}s{C['reset']}"
        else:
            h, rem = divmod(int(seconds), 3600)
            m = rem // 60
            return f"{C['white_b']}{h}h{m}m{C['reset']}"

    # ── Text styling helpers ──────────────────────────────────────────────

    def dim(self, text: str) -> str:
        return f"{C['dim']}{text}{C['reset']}"

    def bold(self, text: str) -> str:
        return f"{C['bold']}{text}{C['reset']}"

    def italic(self, text: str) -> str:
        return f"{C['italic']}{text}{C['reset']}"

    def truncate(self, text: str, width: int) -> str:
        """Truncate text to visible character width."""
        return _truncate(text, width, I["ellipsis"])

    # ── Spinner (context manager) ─────────────────────────────────────────

    @contextmanager
    def spinner(self, text: str = "working"):
        import threading

        stop = threading.Event()
        start_ns = time.monotonic_ns()

        def _spin():
            i = 0
            while not stop.is_set():
                elapsed_s = int((time.monotonic_ns() - start_ns) / 1e9)
                ts = self.elapsed(elapsed_s) if hasattr(self, "elapsed") else f"{elapsed_s}s"
                print(
                    f"\r{C['cyan_b']} {_SPINNER[i % len(_SPINNER)]} "
                    f"{C['white']}{text}{C['reset']}  {ts}",
                    end="",
                )
                i += 1
                stop.wait(0.1)

        t = threading.Thread(target=_spin, daemon=True)
        t.start()
        try:
            yield
        finally:
            stop.set()
            t.join(timeout=0.3)
            print("\r" + " " * (_width()) + "\r", end="")

    # ── Command capture ───────────────────────────────────────────────────

    def capture(self, label: str, cmd: list[str], **kwargs) -> tuple[str, int]:
        """Run a command, capture output, print a one-line status. Returns (stdout, returncode)."""
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, **kwargs)
            out = (proc.stdout + proc.stderr).strip()
            rc = proc.returncode
        except Exception as e:
            out = str(e)
            rc = 1

        if rc == 0:
            self.ok(label)
        else:
            self.fail(f"{label} (exit {rc})")
            if out:
                for line in out.splitlines()[:5]:
                    print(f"       {C['dim']}{line}{C['reset']}")
        return out, rc


# Singleton — import as `from scripts.lib.pretty import pretty`
pretty = _Pretty()
