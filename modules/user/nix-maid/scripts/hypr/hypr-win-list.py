#!/usr/bin/env python3
"""List Hyprland windows in a multi-column rofi picker."""

from __future__ import annotations

import json
import math
import os
import subprocess
import sys

HYPRCTL = "@HYPRCTL@"
if HYPRCTL.startswith("@HYPRCTL@"):
    HYPRCTL = os.environ.get("HYPR_WIN_LIST_HYPRCTL", "hyprctl")
DEBUG = os.environ.get("HYPR_WIN_LIST_DEBUG")


def hypr_json(command: str) -> list[dict] | dict | None:
    result = subprocess.run(
        [HYPRCTL, "-j", command],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    payload = result.stdout.strip()
    if not payload:
        return None
    try:
        return json.loads(payload)
    except json.JSONDecodeError:
        return None


def clean(text: str) -> str:
    return " ".join(text.split())


def clip(text: str, limit: int) -> str:
    text = clean(text)
    if len(text) > limit:
        return text[: limit - 1] + "…"
    return text


TITLE_LIMIT = 36
WORKSPACE_LIMIT = 16
CLASS_LIMIT = 18


def workspace_label(name: str) -> str:
    name = clean(name)
    if not name:
        return ""
    if " " in name:
        head, tail = name.split(" ", 1)
        tail = tail.strip()
        if tail:
            return tail
    return name


def glyph(cls: str) -> str:
    cls = cls.lower()
    table = {
        "firefox": "",
        "floorp": "",
        "kitty": "",
        "term": "",
        "alacritty": "",
        "foot": "",
        "mpv": "",
        "zathura": "",
        "org.pwmt.zathura": "",
        "steam": "",
        "obsidian": "",
        "obs": "",
        "swayimg": "",
    }
    for key, icon in table.items():
        if key in cls:
            return icon
    return ""


def build_entries() -> tuple[list[str], dict[str, dict[str, str]]]:
    clients_raw = hypr_json("clients")
    if not clients_raw:
        return [], {}
    workspaces_raw = hypr_json("workspaces") or []
    active_raw = hypr_json("activewindow") or {}

    workspaces = workspaces_raw
    if isinstance(workspaces_raw, dict) and "workspaces" in workspaces_raw:
        workspaces = workspaces_raw["workspaces"]

    clients = clients_raw
    if isinstance(clients_raw, dict) and "clients" in clients_raw:
        clients = clients_raw["clients"]

    ws_map: dict[int, str] = {}
    for ws in workspaces:
        wid = ws.get("id")
        if isinstance(wid, int):
            ws_map[wid] = clean(ws.get("name") or str(wid))

    special_ids = {
        ws.get("id")
        for ws in workspaces
        if ws.get("special")
        or clean(ws.get("name") or "").startswith("special")
    }

    active_addr = ""
    if isinstance(active_raw, dict):
        active_addr = clean(str(active_raw.get("address") or ""))

    entries: list[str] = []
    meta_by_addr: dict[str, dict[str, str]] = {}

    for client in clients:
        if not isinstance(client, dict):
            continue
        if not client.get("mapped", True):
            continue

        workspace = client.get("workspace")
        wid = None
        wname = ""
        if isinstance(workspace, dict):
            wid = workspace.get("id")
            wname = clean(workspace.get("name") or "")
        elif isinstance(workspace, int):
            wid = workspace
            wname = clean(ws_map.get(workspace, str(workspace)))

        if wid is None:
            continue
        if wid in special_ids:
            continue
        if wname.startswith("special"):
            continue

        addr = clean(str(client.get("address") or ""))
        if not addr or addr == active_addr:
            continue

        cls = clean(client.get("class") or "")
        ttl = clean(client.get("title") or "")
        ws_label = workspace_label(wname)

        display_parts: list[str] = [glyph(cls)]
        workspace_added = False

        if ttl:
            display_parts.append(clip(ttl, TITLE_LIMIT))

        if ws_label and (not ttl or ws_label.casefold() not in ttl.casefold()):
            display_parts.append(f"({clip(ws_label, WORKSPACE_LIMIT)})")
            workspace_added = True

        if not ttl:
            if ws_label and not workspace_added:
                display_parts.append(f"({clip(ws_label, WORKSPACE_LIMIT)})")
            if cls:
                display_parts.append(clip(cls, CLASS_LIMIT))

        display = " ".join(filter(None, display_parts))

        line = f"{display} — {addr}"

        disallowed = {c for c in line if ord(c) < 32 and c != "\t"}
        if disallowed:
            if DEBUG:
                print(
                    f"[hypr-win-list] skipped entry with control chars: {repr(line)}",
                    file=sys.stderr,
                )
            continue
        if DEBUG:
            print(f"[hypr-win-list] entry: {repr(line)}", file=sys.stderr)
        entries.append(line)
        meta_by_addr[addr] = {
            "title": ttl,
            "class": cls,
            "workspace": wname,
        }

    return entries, meta_by_addr


def rofi_command(count: int) -> list[str]:
    columns = max(1, min(3, count))
    if count > 3:
        columns = 3
    lines = max(1, min(6, math.ceil(count / columns)))
    base = [
        "rofi",
        "-dmenu",
        "-matching",
        "fuzzy",
        "-i",
        "-p",
        " Windows",
        "-kb-accept-alt",
        "Alt+Return",
        "-kb-custom-1",
        "Alt+1",
        "-kb-custom-2",
        "Alt+2",
        "-theme",
        "menu-columns",
        "-columns",
        str(columns),
        "-lines",
        str(lines),
    ]
    if DEBUG:
        print(
            f"[hypr-win-list] rofi columns={columns} lines={lines} count={count}",
            file=sys.stderr,
        )
    return base


def run_rofi(entries: list[str]) -> tuple[int, str]:
    input_data = "\n".join(entries) + "\n"
    rofi = subprocess.run(
        rofi_command(len(entries)),
        input=input_data,
        capture_output=True,
        text=True,
    )
    return rofi.returncode, rofi.stdout.strip()


def strip_hidden(text: str) -> str:
    return text.replace("\u200b", "")


def main() -> int:
    entries, meta = build_entries()
    if not entries:
        return 0

    code, selection = run_rofi(entries)
    if code not in (0, 10):
        return 0
    if not selection or " — " not in selection:
        return 0

    display, addr = selection.split(" — ", 1)
    addr = addr.strip()
    info = meta.get(addr, {})

    if code == 10:
        title = info.get("title") or strip_hidden(display)
        subprocess.run(["wl-copy"], input=title, text=True, check=False)
        return 0

    subprocess.run(
        [HYPRCTL, "dispatch", "focuswindow", f"address:{addr}"],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        [HYPRCTL, "dispatch", "bringactivetotop"],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
