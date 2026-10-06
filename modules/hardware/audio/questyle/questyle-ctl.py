#!/usr/bin/env python3
"""questyle-ctl - inspect & talk to the Questyle QCC Dongle Pro2 (USB 0a12:4007).

The dongle is a Bluetooth audio transmitter (QCC/CSR chip, vendor id 0a12).
It shows up as:
  * a USB Audio card - what PipeWire uses, audio goes to the paired headset;
  * HID interface 0 - standard Consumer Control/Telephony (the dongle sends
    media-key presses to the host);
  * HID interface 1 - vendor page 0xFF00, the *proprietary* control channel:
      report id 1  : 62-byte output  (commands -> dongle)
      report id 5  : 254-byte output (extended/long commands)
      report id 2  : 16-byte input   (dongle -> host)
      report id 6  : 12-byte input
      report id 3/4: 62-byte feature (GET/SET_REPORT, dongle answers with EPIPE)
      report id 0xbb/0xcc: 63-byte in/out, 0xfd: 31-byte in/out
  * vendor-specific interface 6 (class 255/240, 2 bulk EPs) - unbound, unused.
The vendor protocol itself is undocumented; `watch` records what the dongle
does say (press its button / connect a headset) and `raw` sends a frame by hand.

Subcommands:
  info                     what the kernel/PipeWire currently see (safe)
  watch [-t N] [--log F]   dump vendor HID input reports (read-only, safe)
  raw HEX                  write one output report (report 1) - expert use
  feature RID [SIZE]       GET_REPORT on the vendor channel (read-only)
"""

from __future__ import annotations

import argparse
import fcntl
import glob
import os
import re
import select
import struct
import subprocess
import sys
import time

VID, PID = 0x0A12, 0x4007
HID_ID = f"0003:{VID:08X}:{PID:08X}"
VENDOR_USAGE_PAGE = 0xFF00
HIDIOCGRDESCSIZE = 0x80044801
HIDIOCGRDESC = 0x90044802


def _ioctl_get_feature(size: int) -> int:
    return 0xC0000000 | ((size + 1) << 16) | (0x48 << 8) | 0x07


def hidraw_nodes() -> list[tuple[str, str]]:
    """Return [(raw_node, sysfs_hid_device), ...] for this device."""
    out = []
    for h in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        try:
            uevent = open(os.path.join(h, "device", "uevent")).read()
        except OSError:
            continue
        if HID_ID in uevent:
            out.append(
                (
                    f"/dev/{os.path.basename(h)}",
                    os.path.realpath(os.path.join(h, "device")),
                )
            )
    return out


def report_descriptor(dev: str) -> bytes:
    fd = os.open(dev, os.O_RDONLY)
    try:
        buf = bytearray(4)
        fcntl.ioctl(fd, HIDIOCGRDESCSIZE, buf, True)
        size = struct.unpack_from("I", buf, 0)[0]
        b = bytearray(4 + size)
        struct.pack_into("I", b, 0, size)
        fcntl.ioctl(fd, HIDIOCGRDESC, b, True)
        return bytes(b[4 : 4 + size])
    finally:
        os.close(fd)


def is_vendor_channel(dev: str) -> bool:
    """True for the HID interface carrying usage page 0xFF00."""
    try:
        d = report_descriptor(dev)
    except OSError:
        return False
    return b"\x06\x00\xff" in d


def vendor_node() -> str | None:
    for dev, _ in hidraw_nodes():
        if is_vendor_channel(dev):
            return dev
    return None


def alsa_card() -> tuple[int, str] | None:
    try:
        cards = open("/proc/asound/cards").read()
    except OSError:
        return None
    for m in re.finditer(
        r"^\s*(\d+)\s*\[([^\]]+)\]:\s*USB-Audio - (.*)$", cards, re.M
    ):
        if "QCC Dongle" in m.group(3) or "Questyle" in m.group(3):
            return int(m.group(1)), m.group(3).strip()
    return None


def usb_info() -> list[str]:
    lines = []
    for d in glob.glob("/sys/bus/usb/devices/*"):
        try:
            idv = open(os.path.join(d, "idVendor")).read().strip()
            idp = open(os.path.join(d, "idProduct")).read().strip()
        except OSError:
            continue
        if (int(idv, 16), int(idp, 16)) != (VID, PID):
            continue

        def rd(name: str) -> str:
            try:
                return open(os.path.join(d, name)).read().strip()
            except OSError:
                return "?"

        lines += [
            f"  sysfs path  : {d}",
            f"  product     : {rd('manufacturer')} {rd('product')}",
            f"  serial      : {rd('serial')}  rev {rd('bcdDevice')}",
            f"  speed       : {rd('speed')} Mbps, max power {rd('bMaxPower')}",
            f"  power/ctl   : autosuspend={rd('power/control')}",
        ]
    return lines


def alsa_info(card: int) -> list[str]:
    lines = []
    try:
        stream = open(f"/proc/asound/card{card}/stream0").read()
    except OSError:
        return ["  (no stream info)"]
    state = fmt = ""
    for line in stream.splitlines():
        s = line.strip()
        if s.startswith("Status:"):
            state = s
        elif s.startswith("Momentary freq"):
            lines.append(f"  {s}")
        elif s.startswith("Format:"):
            fmt = f"{fmt} {s.split(':', 1)[1].strip()}".strip()
    lines.insert(0, f"  playback    : {state}  [{fmt or 'idle'}]")
    return lines


def mixer_info(card: int) -> list[str]:
    try:
        out = subprocess.run(
            ["amixer", "-c", str(card)],
            capture_output=True,
            text=True,
            timeout=5,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return ["  (amixer unavailable)"]
    keep, name = [], ""
    for line in out.splitlines():
        if line.startswith("Simple mixer control"):
            stripped = line.strip()
            name = stripped.split("'")[1] if "'" in stripped else stripped
        elif (
            "Playback" in line
            or "Capture" in line
            or line.strip().startswith("Mono:")
        ):
            keep.append(f"  {name}: {line.strip()}")
    return keep or ["  (no controls)"]


def pipewire_info() -> list[str]:
    try:
        st = subprocess.run(
            ["wpctl", "status"], capture_output=True, text=True, timeout=5
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return ["  (wpctl unavailable)"]
    lines = []
    for line in st.splitlines():
        if "QCC" in line or "Mpow HC5" in line or "Questyle" in line:
            lines.append("  " + line.strip())
    try:
        links = subprocess.run(
            ["pw-link", "-l"], capture_output=True, text=True, timeout=5
        ).stdout
    except (OSError, subprocess.SubprocessError):
        links = ""
    routed = [
        line.strip()
        for line in links.splitlines()
        if "alsa_output.usb-Questyle" in line or "Mpow" in line
    ]
    if routed:
        lines.append("  links:")
        lines += [f"    {line}" for line in routed]
    return lines or ["  (device not in the current PipeWire graph)"]


def cmd_info(_: argparse.Namespace) -> int:
    print("USB")
    for line in usb_info() or ["  (device not found - подключён?)"]:
        print(line)
    print("HID interfaces")
    for dev, sysdev in hidraw_nodes():
        role = (
            "vendor/proprietary control (page 0xFF00)"
            if is_vendor_channel(dev)
            else "consumer control"
        )
        print(f"  {dev:14s} {role}")
    card = alsa_card()
    if card:
        n, name = card
        print(f"ALSA card {n}: {name}")
        for line in alsa_info(n) + mixer_info(n):
            print(line)
    else:
        print("ALSA: (card not found)")
    print("PipeWire")
    for line in pipewire_info():
        print(line)
    return 0


def cmd_watch(a: argparse.Namespace) -> int:
    node = vendor_node()
    if not node:
        print("vendor HID channel not found", file=sys.stderr)
        return 1
    fd = os.open(node, os.O_RDONLY | os.O_NONBLOCK)
    log = open(a.log, "a", buffering=1) if a.log else None
    print(
        f"watching {node} for {a.time}s (read-only; press the dongle's button / connect a headset)"
    )
    end = time.time() + a.time
    try:
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.5)
            if not r:
                continue
            data = os.read(fd, 512)
            ts = time.strftime("%H:%M:%S")
            line = f"[{ts}] rid={data[0]:#04x} len={len(data) - 1} {data[1:].hex(' ')}"
            print(line)
            if log:
                log.write(line + "\n")
    except KeyboardInterrupt:
        pass
    finally:
        os.close(fd)
        if log:
            log.close()
    return 0


def cmd_raw(a: argparse.Namespace) -> int:
    node = vendor_node()
    if not node:
        print("vendor HID channel not found", file=sys.stderr)
        return 1
    payload = bytes.fromhex(a.hex.replace(" ", "").replace(",", ""))
    if not payload:
        print("empty payload", file=sys.stderr)
        return 2
    if (
        payload[0] == 0x00
    ):  # report id comes from the descriptor; 1 = 62-byte output
        payload = bytes([1]) + payload
    print(f"-> {node}: {payload.hex(' ')} ({len(payload)} bytes)")
    fd = os.open(node, os.O_RDWR)
    try:
        n = os.write(fd, payload)
        print(f"write() ok, {n} bytes")
    finally:
        os.close(fd)
    return 0


def cmd_feature(a: argparse.Namespace) -> int:
    node = a.node or vendor_node()
    if not node:
        print("vendor HID channel not found", file=sys.stderr)
        return 1
    fd = os.open(node, os.O_RDWR)
    try:
        buf = bytearray(a.size + 1)
        buf[0] = a.rid & 0xFF
        fcntl.ioctl(fd, _ioctl_get_feature(a.size), buf, True)
        print(f"feature {a.rid:#04x}: {bytes(buf[1:]).hex(' ')}")
    except OSError as e:
        print(f"feature {a.rid:#04x}: {e}", file=sys.stderr)
        return 1
    finally:
        os.close(fd)
    return 0


def main() -> int:
    p = argparse.ArgumentParser(
        prog="questyle-ctl", description=__doc__.splitlines()[0]
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("info", help="device/ALSA/PipeWire state (safe)")

    w = sub.add_parser("watch", help="dump vendor HID input reports")
    w.add_argument("-t", "--time", type=float, default=30.0)
    w.add_argument("--log", help="append reports to this file")

    r = sub.add_parser("raw", help="write a raw output report (report id 1)")
    r.add_argument(
        "hex",
        help="hex bytes, e.g. '00 01 02 ...' (report id prepended if needed)",
    )

    f = sub.add_parser("feature", help="GET_REPORT on the vendor channel")
    f.add_argument("rid", type=lambda s: int(s, 0))
    f.add_argument("size", nargs="?", type=int, default=62)
    f.add_argument("--node", help="override hidraw node")

    a = p.parse_args()
    return {
        "info": cmd_info,
        "watch": cmd_watch,
        "raw": cmd_raw,
        "feature": cmd_feature,
    }[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
