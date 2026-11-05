#!/usr/bin/env python3
"""nightjob — unattended GPU jobs on trantor (RX 9070 XT, ROCm).

The tool covers the three things a long run needs and trainers never ship:

  preflight  which applications hold the Radeon's VRAM right now, and an
             interactive loop that closes the ones you pick until the job's
             budget fits.  VRAM per PID comes from the kernel's DRM fdinfo
             (`drm-total-vram`), so no root, no rocm-smi KFD dependency.

  run        launch a command under a transient systemd user unit with an
             absolute deadline (SIGINT at the end, so the trainer can save a
             checkpoint), retries that resume from that checkpoint, a ROCm CSV
             sampler, a log file and a morning report.

  env        create or check a ROCm training venv (PyTorch ROCm wheels plus
             the Hugging Face stack) for LoRA / from-scratch runs.

State lives in ~/.local/state/nightjob/<unit>/<timestamp>/ and nowhere else.
The CLI is stdlib-only; systemd-run, fzf and rocm-smi come from PATH.
"""

from __future__ import annotations

import argparse
import getpass
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path
from typing import NoReturn

MIB = 1024 * 1024
GIB = 1024 * MIB
STATE_DIR = Path(
    os.environ.get(
        "NIGHTJOB_STATE", str(Path.home() / ".local/state/nightjob")
    )
)
DEFAULT_VENV = Path(os.environ.get("NIGHTJOB_VENV", "/zero/ai/venvs/train"))
TORCH_ROCM_INDEX = "https://download.pytorch.org/whl/rocm7.1"
SAMPLE_SECONDS = float(os.environ.get("NIGHTJOB_SAMPLE_SECONDS", "30"))
STOP_GRACE_SECONDS = 240
UNIT_PREFIX = "nightjob-"

# Processes that must never be killed: the compositor and the session
# plumbing die with the whole desktop, and nightjob's own ancestors include
# the shell that started it.
HARD_PROTECTED = {
    "Hyprland",
    "Xwayland",
    "systemd",
    "systemd-journald",
    "systemd-logind",
    "dbus-daemon",
    "dbus-broker",
    "login",
    "greetd",
    "uwsm",
    "nightjob",
}

# Walk up the parent chain only until one of these; everything above is the
# session, everything below is one application tree.
SESSION_BOUNDARY = {
    "Hyprland",
    "Xwayland",
    "systemd",
    "dbus-daemon",
    "dbus-broker",
    "login",
    "greetd",
    "uwsm",
    # Shells and terminals own their own jobs: an app started from a terminal
    # must stay its own group, otherwise closing "the app" would kill the
    # terminal and every sibling job with it.
    "zsh",
    "bash",
    "fish",
    "sh",
    "tmux",
    "screen",
    "kitty",
    "foot",
    "alacritty",
    "wezterm",
    "konsole",
    "systemd-run",
}

UNIT_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,48}$")


# --------------------------------------------------------------------------
# small helpers


def die(msg: str, code: int = 2) -> NoReturn:
    print(f"nightjob: {msg}", file=sys.stderr)
    raise SystemExit(code)


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    """subprocess.run with text output and a short timeout by default."""
    kwargs.setdefault("text", True)
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("timeout", 10)
    return subprocess.run(cmd, **kwargs)


def read_text(path: str) -> str:
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def human_bytes(n: int) -> str:
    if n >= GIB:
        return f"{n / GIB:.1f} GiB"
    return f"{n / MIB:.0f} MiB"


def human_duration(seconds: float) -> str:
    seconds = max(0, int(seconds))
    hours, rem = divmod(seconds, 3600)
    minutes, sec = divmod(rem, 60)
    if hours:
        return f"{hours}h{minutes:02d}m"
    if minutes:
        return f"{minutes}m{sec:02d}s"
    return f"{sec}s"


def parse_duration(text: str) -> float:
    """Parse 90s / 30m / 8h / 8h30m / 2d into seconds."""
    if not text:
        raise ValueError("empty duration")
    lowered = text.lower().replace(" ", "")
    total = 0.0
    count = 0
    for value, unit in re.findall(r"(\d+(?:\.\d+)?)([smhd])", lowered):
        count += 1
        total += float(value) * {"s": 1, "m": 60, "h": 3600, "d": 86400}[unit]
    leftover = re.sub(r"\d+(?:\.\d+)?[smhd]", "", lowered)
    if count == 0 or leftover:
        raise ValueError(f"cannot parse duration: {text!r}")
    return total


# --------------------------------------------------------------------------
# GPU and process inspection


def pci_slot(device_dir: str) -> str:
    for line in read_text(os.path.join(device_dir, "uevent")).splitlines():
        if line.startswith("PCI_SLOT_NAME="):
            return line.split("=", 1)[1].strip()
    return ""


def gpu_name(device_dir: str, pci: str) -> str:
    """Marketing name via lspci; sysfs only carries the PCI id."""
    if shutil.which("lspci") and pci:
        result = run(["lspci", "-s", pci.split(":", 1)[-1]])
        line = result.stdout.strip()
        marker = "controller: "
        name = line.split(marker, 1)[1].strip() if marker in line else line
        # "… [AMD/ATI] Navi 48 [Radeon RX 9070/…] (rev c0)": the last bracket
        # holds the marketing name people recognise.
        brackets = re.findall(r"\[([^\]]+)\]", name)
        if brackets:
            return brackets[-1]
        return name
    vendor_device = read_text(os.path.join(device_dir, "uevent"))
    for line_text in vendor_device.splitlines():
        if line_text.startswith("PCI_ID="):
            return f"AMD GPU ({line_text.split('=', 1)[1]})"
    return "AMD GPU"


def find_gpu() -> dict:
    """Pick the discrete AMD card: the one with the most VRAM."""
    best = None
    for card in sorted(Path("/sys/class/drm").glob("card[0-9]*")):
        dev = card / "device"
        try:
            vendor = int(read_text(str(dev / "vendor")).strip(), 16)
            total = int(read_text(str(dev / "mem_info_vram_total")).strip())
            used = int(read_text(str(dev / "mem_info_vram_used")).strip())
        except (OSError, ValueError):
            continue
        if vendor != 0x1002 or total < 4 * GIB:
            continue
        slot = pci_slot(str(dev))
        candidate = {
            "card": card.name,
            "device_dir": str(dev),
            "pci": slot,
            "name": gpu_name(str(dev), slot),
            "total": total,
            "used": used,
        }
        if best is None or candidate["total"] > best["total"]:
            best = candidate
    if best is None:
        die("no AMD GPU with VRAM found under /sys/class/drm")
    return best


def gpu_temp_c(device_dir: str) -> int | None:
    temps = []
    for path in Path(device_dir).glob("hwmon/hwmon*/temp*_input"):
        try:
            temps.append(int(read_text(str(path)).strip()) // 1000)
        except (OSError, ValueError):
            continue
    return max(temps) if temps else None


def gpu_power_w(device_dir: str) -> float | None:
    for path in Path(device_dir).glob("hwmon/hwmon*/power1_average"):
        try:
            return int(read_text(str(path)).strip()) / 1_000_000
        except (OSError, ValueError):
            continue
    return None


def gpu_busy_pct(device_dir: str) -> int | None:
    try:
        return int(
            read_text(os.path.join(device_dir, "gpu_busy_percent")).strip()
        )
    except (OSError, ValueError):
        return None


def vram_used(device_dir: str) -> int:
    try:
        return int(
            read_text(os.path.join(device_dir, "mem_info_vram_used")).strip()
        )
    except (OSError, ValueError):
        return 0


def parse_size(text: str) -> int:
    match = re.match(r"(\d+)\s*(\w+)", text.strip())
    if not match:
        return 0
    units = {"B": 1, "KiB": 1024, "MiB": MIB, "GiB": GIB}
    return int(match.group(1)) * units.get(match.group(2), 1)


def vram_by_pid(pci: str) -> dict[int, int]:
    """Sum drm-total-vram for every process that has a client on this GPU.

    The kernel reports each DRM client separately, and buffers shared between
    clients (dma-buf imports, e.g. the compositor showing a window) are
    counted once per client.  The per-process numbers are therefore an upper
    bound and the authoritative figure stays mem_info_vram_used.
    """
    totals: dict[int, int] = {}
    # The kernel repeats one DRM client's stats in every fd that points at
    # that client, so a process with N render fds would be counted N times.
    # Deduplicate on (pid, client id).
    seen: set[tuple[int, str]] = set()
    for entry in Path("/proc").glob("[0-9]*/fdinfo/*"):
        if not entry.is_file():
            continue
        try:
            pid = int(entry.parts[-3])
            text = entry.read_text(errors="replace")
        except (OSError, ValueError):
            continue
        if "drm-driver:\tamdgpu" not in text:
            continue
        pdev = ""
        client = ""
        vram = 0
        for line in text.splitlines():
            if line.startswith("drm-pdev:"):
                pdev = line.split(":", 1)[1].strip()
            elif line.startswith("drm-client-id:"):
                client = line.split(":", 1)[1].strip()
            elif line.startswith("drm-total-vram:"):
                vram = parse_size(line.split(":", 1)[1])
        if pdev != pci or not vram:
            continue
        key = (pid, client)
        if key in seen:
            continue
        seen.add(key)
        totals[pid] = totals.get(pid, 0) + vram
    return totals


def proc_status(pid: int) -> tuple[int, str]:
    """Return (ppid, comm) for a PID, or (0, '') when it vanished."""
    status = read_text(f"/proc/{pid}/status")
    ppid = 0
    comm = ""
    for line in status.splitlines():
        if line.startswith("PPid:"):
            try:
                ppid = int(line.split(":", 1)[1].strip())
            except ValueError:
                ppid = 0
        elif line.startswith("Name:"):
            comm = line.split(":", 1)[1].strip()
    return ppid, comm


GENERIC_INTERPRETERS = {
    "python",
    "python3",
    "python3.12",
    "python3.13",
    "python3.14",
    "bash",
    "sh",
    "zsh",
    "node",
    "env",
}


def proc_name(pid: int) -> str:
    """comm is capped at 15 chars and wrappers prefix a dot; argv[0] is truer."""
    _, comm = proc_status(pid)
    argv0 = read_text(f"/proc/{pid}/cmdline").split("\0", 1)[0].strip()
    # Some launchers stuff a whole command line into argv[0]; a path has no
    # spaces, so only trust argv[0] when it looks like one.
    if argv0 and " " not in argv0:
        base = os.path.basename(argv0)
        if base and base.lower() not in GENERIC_INTERPRETERS:
            return base
    return comm.lstrip(".")


def proc_uid(pid: int) -> int:
    try:
        return os.stat(f"/proc/{pid}").st_uid
    except OSError:
        return -1


def ancestors(pid: int) -> list[int]:
    chain = []
    seen = 0
    while pid > 1 and seen < 64:
        ppid, _ = proc_status(pid)
        if ppid <= 1:
            break
        chain.append(ppid)
        pid = ppid
        seen += 1
    return chain


def app_root(pid: int, cache: dict[int, tuple[int, str]]) -> int:
    """Walk up to the process that owns the whole application tree.

    The walk stops at the compositor, the session manager, a shell or a
    terminal: those own their jobs, and an app started from a terminal must
    remain its own group so that closing it does not take the terminal (and
    every sibling job) down with it.
    """
    current = pid
    seen = 0
    while seen < 64:
        if current not in cache:
            cache[current] = proc_status(current)
        ppid, comm = cache[current]
        if comm in SESSION_BOUNDARY or ppid <= 1:
            return current
        if ppid not in cache:
            cache[ppid] = proc_status(ppid)
        if cache[ppid][1] in SESSION_BOUNDARY:
            return current
        current = ppid
        seen += 1
    return current


def hypr_windows() -> dict[int, list[dict]]:
    """Map PID -> Hyprland windows (class, title) when the compositor answers."""
    if not shutil.which("hyprctl"):
        return {}
    try:
        result = run(["hyprctl", "-j", "clients"], timeout=3)
    except (OSError, subprocess.TimeoutExpired):
        return {}
    if result.returncode != 0:
        return {}
    try:
        clients = json.loads(result.stdout or "[]")
    except json.JSONDecodeError:
        return {}
    windows: dict[int, list[dict]] = {}
    for client in clients:
        pid = client.get("pid")
        if not pid:
            continue
        windows.setdefault(int(pid), []).append(
            {
                "class": client.get("class") or "",
                "title": client.get("title") or "",
            }
        )
    return windows


def collect_apps(gpu: dict, own_ancestors: set[int]) -> list[dict]:
    """Group VRAM-holding processes into application trees."""
    by_pid = vram_by_pid(gpu["pci"])
    windows = hypr_windows()
    cache: dict[int, tuple[int, str]] = {}
    groups: dict[int, list[int]] = {}
    for pid in by_pid:
        groups.setdefault(app_root(pid, cache), []).append(pid)

    apps = []
    for root, pids in groups.items():
        mib = sum(by_pid[p] for p in pids) // MIB
        if mib <= 0:
            continue
        root_comm = proc_name(root)
        titles = []
        for pid in set(pids) | {root}:
            for window in windows.get(pid, []):
                if window["title"]:
                    titles.append(window["title"])
        comms = {proc_status(p)[1] for p in pids}
        name = root_comm.lstrip(".") or "?"
        reason = ""
        protected = False
        if root == 1:
            protected, reason = True, "session"
        elif root_comm in HARD_PROTECTED or comms & {"Hyprland", "Xwayland"}:
            protected, reason = True, "session/compositor"
        elif root in own_ancestors or set(pids) & own_ancestors:
            protected, reason = True, "nightjob's own shell"
        elif any(proc_uid(p) != os.getuid() for p in pids):
            protected, reason = True, "other user"
        note = ""
        if "ollama" in comms:
            note = "system service: `sudo systemctl stop ollama`"
        elif comms & {"llama-server", "llama-swap"}:
            note = "llama-swap backend: `llmctl unload` is the graceful way"
        apps.append(
            {
                "name": name,
                "pids": sorted(pids),
                "mib": mib,
                "protected": protected,
                "reason": reason,
                "note": note,
                "titles": titles[:3],
            }
        )
    apps.sort(key=lambda app: app["mib"], reverse=True)
    return apps


def print_apps(apps: list[dict], total: int) -> None:
    if not apps:
        print("  (no process holds VRAM on this GPU)")
        return
    width = max(len(app["name"]) for app in apps)
    width = min(max(width, 12), 34)
    print(f"  {'APP':<{width}}  {'VRAM':>9}  {'PIDS':<20}  NOTE")
    for app in apps:
        note = app["note"] or (app["reason"] if app["protected"] else "")
        title = app["titles"][0][:56] if app["titles"] else ""
        label = app["name"][:width]
        pids = ",".join(str(p) for p in app["pids"])[:20]
        flag = "  " if not app["protected"] else "* "
        print(
            f"{flag}{label:<{width}}  {human_bytes(app['mib'] * MIB):>9}"
            f"  {pids:<20}  {note or title}"
        )
    allocated = sum(app["mib"] for app in apps)
    print(
        f"\n  per-process sum: {allocated / 1024:.1f} GiB "
        f"(shared buffers counted once per client; "
        f"the GPU reports {total / GIB:.1f} GiB in use)"
    )


# --------------------------------------------------------------------------
# preflight


def preflight_report(gpu: dict, need_mib: int, reserve_mib: int) -> dict:
    apps = collect_apps(gpu, set(ancestors(os.getpid())))
    used = vram_used(gpu["device_dir"])
    free = max(0, gpu["total"] - used)
    need = need_mib * MIB
    reserve = reserve_mib * MIB
    return {
        "gpu": gpu["name"],
        "card": gpu["card"],
        "pci": gpu["pci"],
        "total_mib": gpu["total"] // MIB,
        "used_mib": used // MIB,
        "free_mib": free // MIB,
        "need_mib": need_mib,
        "reserve_mib": reserve_mib,
        "ready": free >= need + reserve,
        "temp_c": gpu_temp_c(gpu["device_dir"]),
        "apps": apps,
    }


def linger_enabled() -> bool | None:
    """False when the user manager dies on logout and takes the job with it."""
    if not shutil.which("loginctl"):
        return None
    user = os.environ.get("USER") or getpass.getuser()
    result = run(["loginctl", "show-user", user, "-p", "Linger"])
    if result.returncode != 0:
        return None
    return result.stdout.strip().endswith("yes")


def preflight_ready(report: dict) -> bool:
    return bool(report["ready"])


def need_mib(args) -> int:
    return int(round(args.need_gb * 1024))


def reserve_mib(args) -> int:
    return int(round(args.reserve_gb * 1024))


def close_apps(apps: list[dict], assume_yes: bool) -> None:
    print()
    for app in apps:
        names = ", ".join(str(p) for p in app["pids"])
        print(f"  closing {app['name']} (pids {names}, {app['mib']} MiB)")
        if app["note"]:
            print(f"    note: {app['note']}")
    if not assume_yes:
        try:
            answer = input("  send SIGTERM to these applications? [y/N] ")
        except EOFError:
            answer = ""
        if answer.strip().lower() not in {"y", "yes", "д", "да"}:
            print("  cancelled")
            return
    for app in apps:
        for pid in app["pids"]:
            if pid in (0, 1) or pid == os.getpid():
                continue
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            except PermissionError:
                print(f"    cannot signal {pid}: permission denied")
    deadline = time.time() + 10
    while time.time() < deadline:
        alive = [pid for app in apps for pid in app["pids"] if _alive(pid)]
        if not alive:
            break
        time.sleep(0.5)
    survivors = [pid for app in apps for pid in app["pids"] if _alive(pid)]
    if survivors:
        print(f"  still alive after 10s: {survivors} (stop them manually)")


def _alive(pid: int) -> bool:
    """A zombie still answers kill(0); read the state to mean it."""
    stat = read_text(f"/proc/{pid}/stat")
    if not stat:
        return False
    try:
        state = stat.rsplit(") ", 1)[1].split(None, 1)[0]
    except IndexError:
        state = ""
    if state == "Z":
        return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def select_apps_fzf(apps: list[dict]) -> list[dict]:
    """Multi-select with fzf; an empty selection means the user cancelled."""
    if not shutil.which("fzf"):
        return []
    lines = []
    for index, app in enumerate(apps, 1):
        title = app["titles"][0][:70] if app["titles"] else app["note"]
        lines.append(
            "\t".join(
                [
                    str(index),
                    app["name"][:32],
                    f"{app['mib']:>6} MiB",
                    title,
                    str(len(app["pids"])),
                ]
            )
        )
    result = subprocess.run(
        [
            "fzf",
            "--multi",
            "--delimiter=\t",
            "--with-nth=2,3,4",
            "--header=TAB: select · ENTER: close · ESC: cancel",
            "--prompt=close > ",
            "--height=~16",
            "--reverse",
        ],
        input="\n".join(lines) + "\n",
        text=True,
        stdout=subprocess.PIPE,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return []
    chosen = []
    for line in result.stdout.splitlines():
        try:
            chosen.append(apps[int(line.split("\t", 1)[0]) - 1])
        except (ValueError, IndexError):
            continue
    return chosen


def cmd_preflight(args) -> int:
    gpu = find_gpu()
    report = preflight_report(gpu, need_mib(args), reserve_mib(args))
    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
        return 0 if report["ready"] else 1

    print(f"GPU     {report['gpu']} ({report['card']}, {report['pci']})")
    print(
        f"VRAM    {report['used_mib'] / 1024:.1f} / "
        f"{report['total_mib'] / 1024:.1f} GiB used · "
        f"{report['free_mib'] / 1024:.1f} GiB free"
    )
    print(
        f"budget  need {args.need_gb:.1f} + reserve "
        f"{args.reserve_gb:.1f} GiB = "
        f"{(args.need_gb + args.reserve_gb):.1f} GiB"
    )
    temp = report["temp_c"]
    print(f"temp    {temp if temp is not None else '?'} °C")
    if temp is not None and temp >= 85:
        print("warn    the GPU is hot; let it cool before a long run")
    disk = _disk_free()
    if disk is not None:
        print(f"disk    {disk:.1f} GiB free on /zero")
    if linger_enabled() is False:
        print(
            "session linger is off: the job stops if you log out "
            "(`loginctl enable-linger $USER` keeps it)"
        )
    print()
    print_apps(report["apps"], gpu["used"])

    closable = [
        app
        for app in report["apps"]
        if not app["protected"] and app["mib"] >= args.min_mib
    ]
    if report["ready"]:
        print("\nready: the job fits, nothing has to be closed")
        return 0

    if args.close:
        wanted = [app for app in closable if _matches(app, args.close)]
        if not wanted:
            die(f"no closable app matches {args.close!r}", 1)
        close_apps(wanted, args.yes)
        return _rescan(gpu, args)

    if args.json or not sys.stdin.isatty() or not shutil.which("fzf"):
        print("\nnot ready: close the apps above, then re-run preflight")
        return 1

    for _round in range(3):
        chosen = select_apps_fzf(closable)
        if not chosen:
            print("\ncancelled: nothing selected")
            return 1
        close_apps(chosen, args.yes)
        code = _rescan(gpu, args)
        if code == 0:
            return 0
        report = preflight_report(gpu, need_mib(args), reserve_mib(args))
        closable = [
            app
            for app in report["apps"]
            if not app["protected"] and app["mib"] >= args.min_mib
        ]
        if not closable:
            break
    print("\nstill not enough VRAM; lower --need-gb or close the rest by hand")
    return 1


def _matches(app: dict, query: str) -> bool:
    haystack = " ".join(
        [app["name"], app["note"], *app["titles"], *_comm_names(app)]
    ).lower()
    return query.lower() in haystack


def _comm_names(app: dict) -> list[str]:
    return [proc_name(pid) for pid in app["pids"]]


def _rescan(gpu: dict, args) -> int:
    time.sleep(1.5)
    report = preflight_report(gpu, need_mib(args), reserve_mib(args))
    print(
        f"\nVRAM now {report['used_mib'] / 1024:.1f} / "
        f"{report['total_mib'] / 1024:.1f} GiB used · "
        f"{report['free_mib'] / 1024:.1f} GiB free"
    )
    if report["ready"]:
        print("ready: the job fits")
        return 0
    print("not ready yet")
    return 1


def _disk_free() -> float | None:
    try:
        usage = shutil.disk_usage("/zero")
    except OSError:
        return None
    return usage.free / GIB


# --------------------------------------------------------------------------
# run metadata and supervision


def state_root() -> Path:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    return STATE_DIR


def unit_name(unit: str) -> str:
    return f"{UNIT_PREFIX}{unit}"


def latest_run(unit: str) -> Path | None:
    root = STATE_DIR / unit
    if not root.is_dir():
        return None
    runs = sorted([p for p in root.iterdir() if p.is_dir()], reverse=True)
    return runs[0] if runs else None


def new_run_dir(unit: str) -> Path:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = state_root() / unit / stamp
    run_dir.mkdir(parents=True, exist_ok=False)
    return run_dir


def write_json(path: Path, data: dict) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    tmp.replace(path)


def read_json(path: Path) -> dict:
    return json.loads(path.read_text())


def cmd_run(args) -> int:
    unit = args.unit
    if not UNIT_RE.match(unit):
        die(f"invalid unit name {unit!r} (letters, digits, _ . - only)")
    if not args.cmd:
        die("no command given (put it after `--`)")
    cmd = list(args.cmd)
    if cmd and cmd[0] == "--":
        cmd = cmd[1:]
    if not cmd:
        die("empty command after `--`")

    if _unit_active(unit):
        die(
            f"{unit_name(unit)} is already running; `nightjob stop -u {unit}` first"
        )

    budget = args.budget_s
    probe = getattr(args, "probe_s", 0)
    if probe:
        budget = probe
    if not args.skip_preflight:
        code = _preflight_for_run(args)
        if code != 0 and not args.force:
            print(
                "preflight failed: free VRAM before the night job, or --force"
            )
            return 1
        if code != 0:
            print("warning: starting without the VRAM budget (--force)")

    # The clock starts after the preflight: closing apps and waiting for the
    # driver to release VRAM must not eat the job's budget.
    run_dir = new_run_dir(unit)
    meta = {
        "unit": unit,
        "cmd": cmd,
        "cwd": os.getcwd(),
        "created": datetime.now().isoformat(timespec="seconds"),
        "deadline": time.time() + budget,
        "budget_s": budget,
        # `retries` is the attempt count; a probe never retries but still runs
        # once.
        "retries": 1 if probe else args.retries,
        "attempt_gap_s": args.attempt_gap_s,
        "resume_arg": args.resume_arg,
        "run_dir": str(run_dir),
        "env": _parse_env(args.env),
        "need_gb": args.need_gb,
    }
    write_json(run_dir / "meta.json", meta)

    unit_full = unit_name(unit)
    # A failed transient unit can linger after `stop`; clear it so the same
    # unit name stays reusable.
    run(["systemctl", "--user", "reset-failed", unit_full])
    systemd_cmd = [
        "systemd-run",
        "--user",
        f"--unit={unit_full}",
        "--collect",
        "--property=Type=exec",
        f"--property=WorkingDirectory={meta['cwd']}",
        "--property=Nice=10",
        # `stop` must reach the supervisor only: the supervisor turns it into
        # SIGINT for the trainer, which is what makes it save a checkpoint.
        # The default (control-group) would SIGTERM the trainer directly.
        "--property=KillMode=mixed",
        f"--property=TimeoutStopSec={STOP_GRACE_SECONDS + 60}",
        f"--setenv=NIGHTJOB_SAMPLE_SECONDS={SAMPLE_SECONDS}",
    ]
    for key, value in meta["env"].items():
        systemd_cmd.append(f"--setenv={key}={value}")
    systemd_cmd += [
        sys.executable,
        os.path.abspath(__file__),
        "_supervise",
        f"--run-dir={run_dir}",
    ]
    if args.dry_run:
        print("would run:")
        print("  " + " \\\n  ".join(_shell_quote(c) for c in systemd_cmd))
        print(f"run dir: {run_dir}")
        return 0
    try:
        result = run(systemd_cmd, timeout=15)
    except OSError as exc:
        die(f"cannot launch systemd-run: {exc}")
    if result.returncode != 0:
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        return 1
    print(f"started {unit_full}")
    print(f"run dir {run_dir}")
    print(f"watch   nightjob status -u {unit}")
    print(f"logs    nightjob logs -u {unit} -f")
    print(f"stop    nightjob stop -u {unit}")
    return 0


def _parse_env(items: list[str]) -> dict[str, str]:
    env = {}
    for item in items:
        if "=" not in item:
            die(f"--env expects KEY=VALUE, got {item!r}")
        key, value = item.split("=", 1)
        env[key] = value
    return env


def _shell_quote(value: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9_./:=@%+-]+", value):
        return value
    return "'" + value.replace("'", "'\\''") + "'"


def _preflight_for_run(args) -> int:
    gpu = find_gpu()
    need, reserve = need_mib(args), reserve_mib(args)
    if preflight_ready(preflight_report(gpu, need, reserve)):
        print("preflight: the VRAM budget fits")
        return 0
    proxy = argparse.Namespace(
        need_gb=args.need_gb,
        reserve_gb=args.reserve_gb,
        min_mib=args.min_mib,
        json=False,
        close=None,
        yes=getattr(args, "yes", False),
    )
    return cmd_preflight(proxy)


def _unit_active(unit: str) -> bool:
    result = run(["systemctl", "--user", "is-active", unit_name(unit)])
    return result.stdout.strip() == "active"


def cmd_supervise(args) -> int:
    run_dir = Path(args.run_dir)
    meta = read_json(run_dir / "meta.json")
    log_path = run_dir / "stdout.log"
    gpu = find_gpu()
    samples: list[dict] = []
    sample_lock = threading.Lock()
    stop_sampling = threading.Event()

    def sample() -> None:
        entry = {
            "ts": time.time(),
            "iso": datetime.now().isoformat(timespec="seconds"),
            "used_mib": vram_used(gpu["device_dir"]) // MIB,
            "temp_c": gpu_temp_c(gpu["device_dir"]),
            "power_w": gpu_power_w(gpu["device_dir"]),
            "busy_pct": gpu_busy_pct(gpu["device_dir"]),
        }
        with sample_lock:
            samples.append(entry)

    sample()
    sampler = threading.Thread(
        target=_sample_loop, args=(stop_sampling, sample), daemon=True
    )
    sampler.start()

    stop = {"flag": False}

    def on_signal(_signum, _frame):
        stop["flag"] = True

    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)

    log = open(log_path, "a", buffering=1, encoding="utf-8")

    def emit(message: str) -> None:
        stamp = datetime.now().strftime("%H:%M:%S")
        line = f"[nightjob {stamp}] {message}"
        print(line, flush=True)
        log.write(line + "\n")

    emit(f"run dir {run_dir}")
    emit(f"command {' '.join(meta['cmd'])}")
    emit(
        f"budget {human_duration(meta['budget_s'])} · "
        f"retries {meta['retries']} · gpu {gpu['name']}"
    )
    rc = None
    attempts = 0
    deadline = meta["deadline"]
    for attempt in range(1, meta["retries"] + 1):
        attempts = attempt
        remaining = deadline - time.time()
        if stop["flag"]:
            emit("stop requested before the attempt")
            break
        if remaining <= 1:
            emit("deadline reached before the attempt")
            break
        cmd = list(meta["cmd"])
        if attempt > 1 and meta["resume_arg"]:
            cmd.append(meta["resume_arg"])
        emit(f"attempt {attempt}/{meta['retries']}: {' '.join(cmd)}")
        try:
            proc = subprocess.Popen(
                cmd,
                cwd=meta["cwd"],
                stdout=log,
                stderr=subprocess.STDOUT,
                start_new_session=True,
                env=_child_env(meta),
            )
        except OSError as exc:
            emit(f"spawn failed: {exc}")
            rc = 127
            break
        rc = _wait_child(proc, deadline, stop, emit)
        emit(f"attempt {attempt} exit {_describe_rc(rc)}")
        if rc == 0 or stop["flag"] or time.time() >= deadline:
            break
        if attempt < meta["retries"]:
            gap = min(meta["attempt_gap_s"], max(0, deadline - time.time()))
            if gap > 0:
                emit(f"retrying in {human_duration(gap)}")
                _sleep_unless(stop, gap)

    stop_sampling.set()
    sampler.join(timeout=2)
    emit("finished")
    final = _final_summary(meta, samples, rc, attempts, log_path)
    write_json(run_dir / "final.json", final)
    _write_report(run_dir, final)
    _notify(meta, final)
    log.close()
    return 0 if final["rc"] == 0 else 1


def _sample_loop(stop_event: threading.Event, sample) -> None:
    while not stop_event.wait(SAMPLE_SECONDS):
        try:
            sample()
        except Exception:  # noqa: BLE001 - a sampler must never kill the run
            continue


def _child_env(meta: dict) -> dict:
    env = dict(os.environ)
    env.setdefault("PYTORCH_HIP_ALLOC_CONF", "expandable_segments:True")
    env.update(meta.get("env") or {})
    return env


def _wait_child(
    proc: subprocess.Popen, deadline: float, stop: dict, emit=print
) -> int:
    """Wait for the child, honouring the deadline and a stop request."""
    while proc.poll() is None:
        now = time.time()
        if stop["flag"]:
            _interrupt(proc, "stop requested", emit)
        elif now >= deadline:
            _interrupt(proc, "deadline reached", emit)
        time.sleep(0.5)
    return proc.returncode


def _interrupt(proc: subprocess.Popen, why: str, emit=print) -> None:
    if proc.poll() is not None:
        return
    emit(f"{why}: SIGINT to {proc.pid}")
    try:
        os.killpg(proc.pid, signal.SIGINT)
    except (ProcessLookupError, PermissionError):
        pass
    try:
        proc.wait(timeout=STOP_GRACE_SECONDS)
    except subprocess.TimeoutExpired:
        emit("graceful stop timed out: SIGKILL")
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass


def _sleep_unless(stop: dict, seconds: float) -> None:
    end = time.time() + seconds
    while time.time() < end and not stop["flag"]:
        time.sleep(1)


def _describe_rc(rc: int | None) -> str:
    if rc is None:
        return "unknown"
    if rc < 0:
        try:
            name = signal.Signals(-rc).name
        except ValueError:
            name = f"signal {-rc}"
        return f"signal {name}"
    return str(rc)


def _final_summary(
    meta: dict, samples: list[dict], rc: int | None, attempts: int, log: Path
) -> dict:
    with_lock = list(samples)
    peak_vram = max((s["used_mib"] for s in with_lock), default=0)
    temp_values = [s["temp_c"] for s in with_lock if s["temp_c"] is not None]
    power_values = [
        s["power_w"] for s in with_lock if s["power_w"] is not None
    ]
    busy_values = [
        s["busy_pct"] for s in with_lock if s["busy_pct"] is not None
    ]
    return {
        "unit": meta["unit"],
        "cmd": meta["cmd"],
        "cwd": meta["cwd"],
        "created": meta["created"],
        "ended": datetime.now().isoformat(timespec="seconds"),
        "duration_s": int(time.time() - (meta["deadline"] - meta["budget_s"])),
        "budget_s": meta["budget_s"],
        "rc": rc,
        "attempts": attempts,
        "peak_vram_mib": peak_vram,
        "peak_temp_c": max(temp_values, default=None),
        "avg_power_w": (
            round(sum(power_values) / len(power_values), 1)
            if power_values
            else None
        ),
        "avg_busy_pct": (
            round(sum(busy_values) / len(busy_values), 1)
            if busy_values
            else None
        ),
        "samples": len(with_lock),
        "log": str(log),
    }


def _write_report(run_dir: Path, final: dict) -> None:
    lines = [
        f"# nightjob {final['unit']} — {final['created']}",
        "",
        f"- command: `{' '.join(final['cmd'])}`",
        f"- exit: {_describe_rc(final['rc'])}",
        f"- attempts: {final['attempts']}",
        f"- duration: {human_duration(final['duration_s'])} "
        f"of {human_duration(final['budget_s'])}",
        f"- VRAM peak: {final['peak_vram_mib'] / 1024:.1f} GiB",
        f"- temp peak: {final['peak_temp_c']} °C",
        f"- power avg: {final['avg_power_w']} W · "
        f"busy avg: {final['avg_busy_pct']} %",
        "",
        "## log tail",
        "",
        "```",
        _tail(final["log"], 40),
        "```",
        "",
    ]
    (run_dir / "report.md").write_text("\n".join(lines), encoding="utf-8")


def _tail(path: str, lines: int) -> str:
    text = read_text(path)
    return "\n".join(text.splitlines()[-lines:])


def _notify(meta: dict, final: dict) -> None:
    if not shutil.which("notify-send"):
        return
    state = "ok" if final["rc"] == 0 else "failed"
    body = (
        f"{state} · {human_duration(final['duration_s'])} · "
        f"peak {final['peak_vram_mib'] / 1024:.1f} GiB · "
        f"{final['peak_temp_c']} °C"
    )
    try:
        run(
            [
                "notify-send",
                "-a",
                "nightjob",
                f"nightjob {meta['unit']} {state}",
                body,
            ],
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        pass


# --------------------------------------------------------------------------
# inspection commands


def cmd_status(args) -> int:
    unit = unit_name(args.unit)
    result = run(
        [
            "systemctl",
            "--user",
            "show",
            unit,
            "--property=ActiveState,SubState,Result,ExecMainStartTimestamp",
        ]
    )
    fields = dict(
        line.split("=", 1)
        for line in result.stdout.splitlines()
        if "=" in line
    )
    print(f"unit    {unit}")
    print(
        f"state   {fields.get('ActiveState', '?')}/"
        f"{fields.get('SubState', '?')} ({fields.get('Result') or 'running'})"
    )
    if fields.get("ExecMainStartTimestamp"):
        print(f"started {fields['ExecMainStartTimestamp']}")
    run_dir = latest_run(args.unit)
    if run_dir is None:
        print("runs    none")
        return 0 if fields.get("ActiveState") == "active" else 3
    print(f"run     {run_dir}")
    log = run_dir / "stdout.log"
    if log.exists():
        tail = _tail(str(log), 8)
        if tail:
            print("\nlog tail:")
            print(tail)
    if (run_dir / "final.json").exists():
        final = read_json(run_dir / "final.json")
        print(
            f"\nresult  exit {_describe_rc(final['rc'])} · "
            f"{human_duration(final['duration_s'])} · "
            f"peak {final['peak_vram_mib'] / 1024:.1f} GiB · "
            f"{final['peak_temp_c']} °C"
        )
        print(f"report  nightjob report -u {args.unit}")
    return 0


def cmd_logs(args) -> int:
    unit = unit_name(args.unit)
    if args.file:
        run_dir = latest_run(args.unit)
        if run_dir is None:
            die("no runs yet")
        path = run_dir / "stdout.log"
        if not path.exists():
            die(f"no log at {path}")
        argv = ["tail"]
        if args.follow:
            argv.append("-f")
        argv += ["-n", str(args.lines), str(path)]
        return subprocess.call(argv)
    cmd = ["journalctl", "--user", "-u", unit, "-n", str(args.lines)]
    if args.follow:
        cmd.append("-f")
    return subprocess.call(cmd)


def cmd_stop(args) -> int:
    unit = unit_name(args.unit)
    result = run(["systemctl", "--user", "stop", unit], timeout=30)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        return 1
    print(
        f"stopped {unit} (the trainer gets SIGINT, then "
        f"{STOP_GRACE_SECONDS}s to save a checkpoint)"
    )
    return 0


def cmd_report(args) -> int:
    run_dir = Path(args.run) if args.run else latest_run(args.unit)
    if run_dir is None or not run_dir.is_dir():
        die("no run directory found")
    final_path = run_dir / "final.json"
    if final_path.exists():
        final = read_json(final_path)
        print(f"unit     {final['unit']}")
        print(f"command  {' '.join(final['cmd'])}")
        print(
            f"exit     {_describe_rc(final['rc'])} "
            f"after {final['attempts']} attempt(s)"
        )
        print(
            f"duration {human_duration(final['duration_s'])} of "
            f"{human_duration(final['budget_s'])}"
        )
        print(
            f"gpu      peak {final['peak_vram_mib'] / 1024:.1f} GiB · "
            f"{final['peak_temp_c']} °C · "
            f"{final['avg_power_w']} W avg"
        )
    else:
        print(f"still running (or crashed before the summary): {run_dir}")
    text = read_text(str(run_dir / "stdout.log"))
    lines = text.splitlines()
    if args.grep:
        lines = [line for line in lines if re.search(args.grep, line)]
    print()
    for line in lines[-args.lines :]:
        print(line)
    return 0


# --------------------------------------------------------------------------
# training environment


def venv_python(venv: Path) -> Path:
    return venv / "bin" / "python"


def cmd_env(args) -> int:
    venv = Path(args.venv)
    python = venv_python(venv)
    if args.action == "check":
        if not python.exists():
            print(f"no venv at {venv}")
            print(f"create it: nightjob env init --venv {venv}")
            return 1
        probe = (
            "import sys\n"
            "print('python', sys.version.split()[0])\n"
            "try:\n"
            "    import torch\n"
            "    print('torch', torch.__version__, "
            "'hip', getattr(torch.version, 'hip', None))\n"
            "    print('device', torch.cuda.get_device_name(0)"
            " if torch.cuda.is_available() else 'unavailable')\n"
            "except Exception as exc:\n"
            "    print('torch import failed:', exc)\n"
            "try:\n"
            "    import transformers, peft, datasets\n"
            "    print('hf', transformers.__version__, peft.__version__,"
            " datasets.__version__)\n"
            "except Exception as exc:\n"
            "    print('hf stack missing:', exc)\n"
        )
        return subprocess.call([str(python), "-c", probe])
    return _env_init(args)


def _env_init(args) -> int:
    venv = Path(args.venv)
    if venv_python(venv).exists() and not args.recreate:
        print(f"venv already exists: {venv} (use --recreate to rebuild)")
        return 1
    steps = [
        [sys.executable, "-m", "venv", str(venv)],
        [
            str(venv_python(venv)),
            "-m",
            "pip",
            "install",
            "--upgrade",
            "pip",
            "wheel",
        ],
        [
            str(venv_python(venv)),
            "-m",
            "pip",
            "install",
            "--index-url",
            args.torch_index,
            "torch",
            "torchvision",
        ],
        [
            str(venv_python(venv)),
            "-m",
            "pip",
            "install",
            "transformers",
            "datasets",
            "accelerate",
            "peft",
            "safetensors",
            "sentencepiece",
            "protobuf",
            "tensorboard",
            "tqdm",
        ],
    ]
    if args.recreate and venv.exists():
        import shutil as _shutil

        _shutil.rmtree(venv)
    print(f"creating {venv} (several GB on first run)")
    for step in steps:
        print("  $ " + " ".join(_shell_quote(part) for part in step))
        if args.dry_run:
            continue
        result = subprocess.run(step, text=True)
        if result.returncode != 0:
            print(f"failed: {' '.join(step)}", file=sys.stderr)
            return 1
    print("\ndone. run jobs with:")
    print(f"  nightjob run --need-gb 12 -- {venv_python(venv)} train.py")
    return 0


# --------------------------------------------------------------------------
# argument parsing


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="nightjob",
        description="Overnight GPU jobs: VRAM preflight, systemd runner, "
        "ROCm training venv.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    def add_gpu_args(p):
        p.add_argument(
            "--need-gb",
            type=float,
            default=12.0,
            help="VRAM the job needs (default: 12)",
        )
        p.add_argument(
            "--reserve-gb",
            type=float,
            default=1.0,
            help="headroom left for the desktop (default: 1)",
        )
        p.add_argument(
            "--min-mib",
            type=int,
            default=128,
            help="ignore apps below this allocation (default: 128)",
        )

    pre = sub.add_parser("preflight", help="check and free VRAM")
    add_gpu_args(pre)
    pre.add_argument("--json", action="store_true", help="machine output")
    pre.add_argument(
        "--close",
        metavar="NAME",
        help="close matching apps without the fzf picker",
    )
    pre.add_argument(
        "--yes", action="store_true", help="skip the confirmation prompt"
    )

    runner = sub.add_parser("run", help="launch an overnight job")
    add_gpu_args(runner)
    runner.add_argument("-u", "--unit", default="main", help="unit suffix")
    runner.add_argument(
        "--budget",
        default="8h",
        help="wall clock budget, e.g. 8h / 90m (default: 8h)",
    )
    runner.add_argument(
        "--retries",
        type=int,
        default=3,
        help="attempts on failure (default: 3)",
    )
    runner.add_argument(
        "--attempt-gap",
        default="60s",
        help="pause between attempts (default: 60s)",
    )
    runner.add_argument(
        "--resume-arg",
        default="--resume",
        help="argument appended on retries (default: --resume)",
    )
    runner.add_argument(
        "--probe",
        metavar="DURATION",
        help="short run without retries, e.g. --probe 2m",
    )
    runner.add_argument(
        "--env",
        action="append",
        default=[],
        metavar="KEY=VALUE",
        help="extra environment for the job (repeatable)",
    )
    runner.add_argument(
        "--skip-preflight", action="store_true", help="do not check VRAM"
    )
    runner.add_argument(
        "--yes", action="store_true", help="skip the close confirmation"
    )
    runner.add_argument(
        "--force", action="store_true", help="start even if VRAM is short"
    )
    runner.add_argument(
        "--dry-run", action="store_true", help="print the systemd command"
    )
    runner.add_argument("cmd", nargs=argparse.REMAINDER)

    status = sub.add_parser("status", help="show the unit and latest run")
    status.add_argument("-u", "--unit", default="main")

    logs = sub.add_parser("logs", help="journal or run log")
    logs.add_argument("-u", "--unit", default="main")
    logs.add_argument("-n", "--lines", type=int, default=40)
    logs.add_argument("-f", "--follow", action="store_true")
    logs.add_argument(
        "--file", action="store_true", help="tail the run log, not the journal"
    )

    stop = sub.add_parser("stop", help="stop the job (SIGINT, then a grace)")
    stop.add_argument("-u", "--unit", default="main")

    report = sub.add_parser("report", help="summarize the latest run")
    report.add_argument("-u", "--unit", default="main")
    report.add_argument("--run", help="explicit run directory")
    report.add_argument("-n", "--lines", type=int, default=40)
    report.add_argument("--grep", help="only log lines matching this regex")

    env = sub.add_parser("env", help="ROCm training venv")
    env.add_argument("action", choices=["init", "check"])
    env.add_argument("--venv", default=str(DEFAULT_VENV))
    env.add_argument(
        "--torch-index", default=TORCH_ROCM_INDEX, help="PyTorch wheel index"
    )
    env.add_argument("--recreate", action="store_true")
    env.add_argument("--dry-run", action="store_true")

    sup = sub.add_parser("_supervise")
    sup.add_argument("--run-dir", required=True)
    return parser


def main(argv: list[str]) -> int:
    parser = build_parser()

    args = parser.parse_args(argv)
    if hasattr(args, "budget"):
        try:
            args.budget_s = parse_duration(args.budget)
        except ValueError as exc:
            die(str(exc))
    if hasattr(args, "probe") and args.probe:
        try:
            args.probe_s = parse_duration(args.probe)
        except ValueError as exc:
            die(str(exc))
    if hasattr(args, "attempt_gap"):
        try:
            args.attempt_gap_s = parse_duration(args.attempt_gap)
        except ValueError as exc:
            die(str(exc))

    handlers = {
        "preflight": cmd_preflight,
        "run": cmd_run,
        "status": cmd_status,
        "logs": cmd_logs,
        "stop": cmd_stop,
        "report": cmd_report,
        "env": cmd_env,
        "_supervise": cmd_supervise,
    }
    try:
        return handlers[args.command](args)
    except KeyboardInterrupt:
        print("interrupted", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
