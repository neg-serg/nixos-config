#!/usr/bin/env python3
# Keyboard-only range selection from kitty scrollback and screen.
# Picks start and end lines via fzf and copies the range to clipboard.

import os
import re
import shutil
import subprocess
import sys


def have(cmd: str) -> bool:
    return shutil.which(cmd) is not None


def get_scrollback() -> str:
    """Fetch the current window's screen + scrollback text via kitty remote control.

    Uses KITTY_LISTEN_ON and KITTY_WINDOW_ID for precise targeting.
    Strips ANSI/OSC escape sequences so fzf displays plain text instead of control codes.
    """
    base = ["kitty", "@"]
    to = os.environ.get("KITTY_LISTEN_ON")
    if to:
        base += ["--to", to]
    win_id = os.environ.get("KITTY_WINDOW_ID")
    cmd = base + ["get-text", "--extent=all"]
    if win_id:
        cmd = base + ["get-text", "--match", f"id:{win_id}", "--extent=all"]
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
    except Exception:
        # Fallback to just the screen if "all" fails for any reason
        try:
            out = subprocess.check_output(
                base + ["get-text", "--extent=screen"], stderr=subprocess.DEVNULL
            )
        except Exception as e:
            print(f"Failed to get scrollback: {e}", file=sys.stderr)
            sys.exit(1)
    text = out.decode("utf-8", "replace")
    return strip_escapes(text)


# Regexes to strip ANSI (CSI), OSC and other escapes so fzf renders content
_re_csi = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
_re_osc = re.compile(r"\x1b\][^\x07\x1b]*(\x07|\x1b\\)")
_re_ss3 = re.compile(r"\x1bO.")
_re_misc = re.compile(r"\x1b[@-Z\-_]")


def strip_escapes(s: str) -> str:
    s = _re_osc.sub("", s)
    s = _re_csi.sub("", s)
    s = _re_ss3.sub("", s)
    s = _re_misc.sub("", s)
    return s


def pick_line(lines, prompt: str) -> int:
    # Present numbered lines in fzf and return the chosen line number (1-based)
    # To avoid huge pipes, stream via a subprocess and add numbers with `nl`.
    env = os.environ.copy()
    env.setdefault("FZF_DEFAULT_OPTS", "--no-sort --ansi --height=90%")

    try:
        nl = subprocess.Popen(
            ["nl", "-ba", "-w1", "-s\t"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
        )
    except FileNotFoundError:
        print("nl not found (coreutils). Please install it.", file=sys.stderr)
        sys.exit(1)

    try:
        fzf = subprocess.Popen(
            [
                "fzf",
                "--ansi",
                "--prompt",
                prompt,
                "--tabstop=4",
                "--bind",
                "home:first,end:last",
                "--layout=reverse",
            ],
            stdin=nl.stdout,
            stdout=subprocess.PIPE,
            env=env,
        )
    except FileNotFoundError:
        print("fzf not found. Please install fzf.", file=sys.stderr)
        sys.exit(1)

    # Feed content to `nl`
    try:
        nl.stdin.write("".join(lines).encode("utf-8", "replace"))
        nl.stdin.close()
    except BrokenPipeError:
        pass

    sel = fzf.communicate()[0] or b""
    if not sel:
        print("Selection cancelled", file=sys.stderr)
        sys.exit(1)
    # Expect lines like: "123\t...."
    try:
        head = sel.decode("utf-8", "replace").splitlines()[0]
        num = int(head.split("\t", 1)[0].strip())
        return num
    except Exception:
        print("Could not parse selected line number", file=sys.stderr)
        sys.exit(1)


def copy_to_clipboard(text: str) -> None:
    # Prefer wl-copy, then xclip, then pbcopy; fallback to kitty kitten clipboard
    data = text.encode("utf-8", "replace")
    if have("wl-copy"):
        subprocess.run(["wl-copy", "-n"], input=data)
        return
    if have("xclip"):
        subprocess.run(["xclip", "-selection", "clipboard"], input=data)
        return
    if have("pbcopy"):
        subprocess.run(["pbcopy"], input=data)
        return
    # Fallback: kitty clipboard kitten
    try:
        subprocess.run(["kitty", "+kitten", "clipboard"], input=data)
    except Exception:
        # Last resort: print to stdout
        sys.stdout.buffer.write(data)


def main(args=None) -> None:
    buf = get_scrollback()
    # Represent as a list of lines preserving trailing spaces
    # Ensure trailing newline so nl counts the last line as well
    if not buf.endswith("\n"):
        buf += "\n"
    lines = buf.splitlines(keepends=True)

    start = pick_line(lines, "start> ")
    end = pick_line(lines, "end> ")
    if end < start:
        start, end = end, start
    # Slice inclusive
    start_idx = max(0, start - 1)
    end_idx = min(len(lines), end)
    chunk = "".join(lines[start_idx:end_idx])
    copy_to_clipboard(chunk)


if __name__ == "__main__":
    main()
