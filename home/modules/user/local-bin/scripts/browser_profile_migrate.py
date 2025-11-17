#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Bidirectional Firefox <-> Floorp profile migration for Linux.

Key behavior changes (read this):
- DEFAULT: write INTO destination's existing *default* profile directory.
  *No new profile IDs are created unless you pass --new-profile.*
- Flat vs "Profiles/": auto-detected from destination profiles.ini (Floorp is flat).
- Case-preserving INI handling (canonical keys: Name, IsRelative, Path, Default).
- Robust read of legacy mixed/lower-case keys.
- Installs: installs.ini is updated; if missing, a minimal one is created so the browser opens the migrated profile.
- NEW: INI writer uses no spaces around '=' (key=value) + validation that enforces this.

Features
--------
- Migrate both ways with --from/--to (firefox|floorp).
- Honors IsRelative in profiles.ini (0/1) for PATH writes.
- Validates presence of key files (places.sqlite, logins.json, key4.db).
  * Default: warns if missing, continues.
  * With --strict: aborts if any are missing.
- Timestamped backup of destination profiles.ini and installs.ini (if exist).
- Process check with/without `pgrep` (refuse to run if source/dest app is running).
- Optional fast copy via rsync (--rsync, --rsync-args "...").
- Skips lock files; deletes compatibility.ini in destination (forces re-detection).
- Can create a brand-new destination profile with --new-profile (and set it default).

Usage examples
--------------
# Firefox -> Floorp (copy into Floorp's *existing default* profile; rsync fast copy)
./browser_profile_migrate.py --from firefox --to floorp --rsync

# Floorp -> Firefox (strict validation; overwrite existing default profile)
./browser_profile_migrate.py --from floorp --to firefox --strict

# Firefox -> Floorp (create a NEW dest profile and set it default)
./browser_profile_migrate.py --from firefox --to floorp --new-profile

# Force proceed if backups already exist, show rsync progress, custom args
./browser_profile_migrate.py --from firefox --to floorp --force --rsync --rsync-args "--info=progress2"

Notes
-----
- Linux-only.
- Destination default profile is detected from profiles.ini ([ProfileX] with Default=1).
- If destination has no profiles.ini, a fresh one is created with a single default profile.
- If installs.ini is absent, we create a minimal file with [General] Version=2 and a synthetic [InstallMigrated].
"""

from __future__ import annotations
import argparse
import configparser
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Optional, Tuple

APP_DIRS = {
    "firefox": Path.home() / ".mozilla" / "firefox",
    "floorp": Path.home() / ".floorp",
}

KEY_FILES = ["places.sqlite", "logins.json", "key4.db"]


def die(msg: str, code: int = 1) -> None:
    print(msg, file=sys.stderr)
    sys.exit(code)


def info(msg: str) -> None:
    print(msg)


def warn(msg: str) -> None:
    print(f"WARNING: {msg}")


def backup_file(p: Path) -> Optional[Path]:
    if not p.exists():
        return None
    ts = time.strftime("%Y%m%d-%H%M%S")
    backup = p.with_suffix(p.suffix + f".bak-{ts}")
    shutil.copy2(p, backup)
    return backup


def app_running(process_hint: str) -> bool:
    # Try pgrep; fall back to /proc scan
    try:
        res = subprocess.run(
            ["pgrep", "-fl", process_hint],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
            text=True,
        )
        if res.returncode == 0 and res.stdout.strip():
            return True
    except FileNotFoundError:
        pass
    # Fallback (very rough)
    proc = Path("/proc")
    for pid_dir in proc.iterdir():
        if not pid_dir.name.isdigit():
            continue
        try:
            cmdline = (pid_dir / "cmdline").read_text(errors="ignore")
            if process_hint in cmdline:
                return True
        except Exception:
            pass
    return False


def new_config() -> configparser.ConfigParser:
    cfg = configparser.ConfigParser(interpolation=None)
    cfg.optionxform = str  # preserve case
    return cfg


def read_ini(path: Path) -> configparser.ConfigParser:
    cfg = new_config()
    if path.exists():
        with path.open("r", encoding="utf-8") as f:
            cfg.read_file(f)
    return cfg


def get_val(
    section: configparser.SectionProxy, key: str, default: Optional[str] = None
) -> Optional[str]:
    # Tolerant getter: try canonical and common lowercase
    if key in section:
        return section[key]
    lk = key.lower()
    for k in section.keys():
        if k.lower() == lk:
            return section[k]
    return default


def set_val(section: configparser.SectionProxy, key: str, value: str) -> None:
    # Writer always uses canonical keys
    section[key] = value


def write_ini_strict(cfg: configparser.ConfigParser, path: Path) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        for section in cfg.sections():
            f.write(f"[{section}]\n")
            for key, value in cfg.items(section):
                f.write(f"{key}={value}\n")  # strict: no spaces around '='
            f.write("\n")
    # Validate formatting
    content = tmp.read_text(encoding="utf-8")
    for line in content.splitlines():
        if line.startswith("[") or line.strip() == "":
            continue
        if "=" not in line:
            tmp.unlink(missing_ok=True)
            die(f"Invalid INI formatting in output: missing '=' in line: {line}")
        key, val = line.split("=", 1)
        if key.endswith(" ") or val.startswith(" "):
            tmp.unlink(missing_ok=True)
            die(f"Invalid INI formatting (spaces around '=') in line: {line}")
    tmp.replace(path)


def profiles_ini_path(app: str) -> Path:
    return APP_DIRS[app] / "profiles.ini"


def installs_ini_path(app: str) -> Path:
    return APP_DIRS[app] / "installs.ini"


def detect_flat_profiles(app: str) -> bool:
    ini = profiles_ini_path(app)
    cfg = read_ini(ini)
    # Floorp typically uses flat profile paths (no Profiles/), Firefox uses Profiles/
    for sec in cfg.sections():
        if not sec.lower().startswith("profile"):
            continue
        p = get_val(cfg[sec], "Path", "") or ""
        if p and "Profiles/" in p:
            return False
    return True


def find_default_profile_dir(app: str) -> Tuple[Path, str]:
    base = APP_DIRS[app]
    ini = profiles_ini_path(app)
    cfg = read_ini(ini)
    flat = detect_flat_profiles(app)
    default_section = None
    for sec in cfg.sections():
        if not sec.lower().startswith("profile"):
            continue
        if get_val(cfg[sec], "Default", "0") == "1":
            default_section = sec
            break
    if default_section is None:
        # No default: pick first profile or create a new minimal one
        for sec in cfg.sections():
            if sec.lower().startswith("profile"):
                default_section = sec
                break
    if default_section is None:
        # Create a minimal profiles.ini with one default profile
        cfg = new_config()
        sec_name = "ProfileMigrated"
        cfg[sec_name] = {}
        set_val(cfg[sec_name], "Name", "default")
        set_val(cfg[sec_name], "IsRelative", "1")
        path_str = "default" if flat else "Profiles/default"
        set_val(cfg[sec_name], "Path", path_str)
        set_val(cfg[sec_name], "Default", "1")
        base.mkdir(parents=True, exist_ok=True)
        write_ini_strict(cfg, ini)
        profile_dir = base / path_str
        profile_dir.mkdir(parents=True, exist_ok=True)
        return (profile_dir, path_str)

    # Resolve path from existing default
    sec = cfg[default_section]
    path_str = get_val(sec, "Path", "") or ""
    isrel = get_val(sec, "IsRelative", "1") == "1"
    if not path_str:
        die(f"profiles.ini for {app} has a default profile without Path")
    p = Path(path_str)
    profile_dir = (base / p) if isrel else p
    return (profile_dir, path_str)


def pick_source_default_profile(app: str) -> Tuple[Path, str]:
    return find_default_profile_dir(app)


def pick_dest_profile(
    app: str, create_new: bool, new_id: Optional[str]
) -> Tuple[Path, str, bool, bool]:
    base = APP_DIRS[app]
    flat = detect_flat_profiles(app)
    if not create_new:
        # Use existing default
        dir_, path_str = find_default_profile_dir(app)
        dir_.mkdir(parents=True, exist_ok=True)
        return (dir_, path_str, flat, False)

    # Create a new profile path
    if new_id:
        if not re.match(r"^[A-Za-z0-9._-]+$", new_id):
            die("--new-id contains unsupported characters")
        path_str = new_id
    else:
        ts = time.strftime("%Y%m%d-%H%M%S")
        path_str = f"migrated-{ts}"
    if not flat and not path_str.startswith("Profiles/"):
        path_str = "Profiles/" + path_str
    dir_ = base / path_str
    dir_.mkdir(parents=True, exist_ok=True)
    return (dir_, path_str, flat, True)


def ensure_general(cfg: configparser.ConfigParser) -> None:
    if not cfg.has_section("General"):
        cfg["General"] = {}
        cfg["General"]["StartWithLastProfile"] = "1"
        cfg["General"]["Version"] = "2"


def update_profiles_ini(
    app: str, path_str: str, make_default: bool = True, create_if_missing: bool = True
) -> None:
    p_ini = profiles_ini_path(app)
    cfg = read_ini(p_ini)
    if not cfg.sections() and not create_if_missing:
        return
    ensure_general(cfg)

    # Find an existing profile section for this path or create a new one
    existing = [(name, cfg[name]) for name in cfg.sections() if name.lower().startswith("profile")]
    target_sec_name = None
    for name, sec in existing:
        if get_val(sec, "Path", "") == path_str:
            target_sec_name = name
            break
    if target_sec_name is None:
        idx = len(existing)
        target_sec_name = f"Profile{idx}"
        cfg[target_sec_name] = {}
        set_val(cfg[target_sec_name], "Name", "default")

    # Update section
    sec = cfg[target_sec_name]
    sec["IsRelative"] = "1"
    sec["Path"] = path_str
    if make_default:
        sec["Default"] = "1"
        # Reset Default=0 for others
        for name, other in existing:
            if name != target_sec_name and "Default" in other:
                other["Default"] = "0"

    write_ini_strict(cfg, p_ini)
    info(f"Updated {app} profiles.ini")


def update_or_create_installs_ini(app: str, profile_path_str: str) -> None:
    i_ini = installs_ini_path(app)
    cfg = read_ini(i_ini)

    install_secs = [s for s in cfg.sections() if s.startswith("Install")]
    if not install_secs:
        ensure_general(cfg)
        sec_name = "InstallMigrated"
        cfg[sec_name] = {}
        cfg[sec_name]["Default"] = profile_path_str
        cfg[sec_name]["Locked"] = "1"
    else:
        for s in install_secs:
            cfg[s]["Default"] = profile_path_str
            if "Locked" not in cfg[s]:
                cfg[s]["Locked"] = "1"

    if not i_ini.exists():
        info("installs.ini not found; it will be created.")

    write_ini_strict(cfg, i_ini)
    info(f"Updated {app} installs.ini")


def copy_profile(src: Path, dst: Path, use_rsync: bool, rsync_args: str) -> None:
    # Clean destination but keep directory itself
    for p in dst.iterdir():
        if p.is_dir():
            shutil.rmtree(p)
        else:
            p.unlink(missing_ok=True)

    # Exclude lock files and compatibility.ini from copy
    if use_rsync:
        rsync_bin = shutil.which("rsync") or "/run/current-system/sw/bin/rsync"
        cmd = [rsync_bin, "-a"]
        if rsync_args:
            cmd.extend(rsync_args.split())
        cmd += [
            "--exclude",
            "*.lock",
            "--exclude",
            "parent.lock",
            "--exclude",
            "lock",
            "--exclude",
            "compatibility.ini",
        ]
        cmd += [str(src) + "/", str(dst)]
        info(f"(rsync) {' '.join(cmd)}")
        subprocess.run(cmd, check=True)
    else:
        for root, dirs, files in os.walk(src):
            rel = Path(root).relative_to(src)
            target_dir = dst / rel
            target_dir.mkdir(parents=True, exist_ok=True)
            for d in dirs:
                (target_dir / d).mkdir(exist_ok=True)
            for f in files:
                if f.endswith(".lock") or f in ("parent.lock", "lock", "compatibility.ini"):
                    continue
                shutil.copy2(Path(root) / f, target_dir / f)

    # Ensure compatibility.ini absent
    (dst / "compatibility.ini").unlink(missing_ok=True)


def validate_key_files(dir_: Path, strict: bool) -> None:
    missing = [k for k in KEY_FILES if not (dir_ / k).exists()]
    if missing:
        msg = f"Key files missing in {dir_}: {', '.join(missing)}"
        if strict:
            die(msg)
        else:
            warn(msg + " (continuing)")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Bidirectional Firefox <-> Floorp profile migration (Linux)."
    )
    p.add_argument("--from", dest="src_app", choices=("firefox", "floorp"), required=True)
    p.add_argument("--to", dest="dst_app", choices=("firefox", "floorp"), required=True)
    p.add_argument(
        "--strict", action="store_true", help="Abort if key files are missing in source."
    )
    p.add_argument(
        "--force", action="store_true", help="Proceed even if apps are running (NOT recommended)."
    )
    p.add_argument("--rsync", action="store_true", help="Use rsync for faster copying.")
    p.add_argument(
        "--rsync-args",
        default="--info=progress2",
        help="Extra rsync args (default: --info=progress2).",
    )
    p.add_argument(
        "--new-profile",
        action="store_true",
        help="Create a NEW destination profile and set it default.",
    )
    p.add_argument(
        "--new-id",
        default=None,
        help="When --new-profile, use this exact profile id (e.g., abcd1234.default).",
    )
    return p.parse_args()


def main() -> None:
    args = parse_args()
    src_app = args.src_app
    dst_app = args.dst_app
    if src_app == dst_app:
        die("Source and destination app must differ.")

    # Safety: refuse to run if apps are running (unless --force)
    if not args.force:
        if app_running(src_app):
            die(f"{src_app} seems to be running; close it or use --force.")
        if app_running(dst_app):
            die(f"{dst_app} seems to be running; close it or use --force.")

    # Locate source default profile
    src_dir, _src_path_str = pick_source_default_profile(src_app)
    validate_key_files(src_dir, args.strict)

    # Determine destination profile (existing default by default)
    dst_dir, dst_path_str, _flat, created_new = pick_dest_profile(
        dst_app, args.new_profile, args.new_id
    )

    info(f"Source ({src_app}) profile: {src_dir}")
    info(f"Destination ({dst_app}) profile: {dst_dir}")

    # Copy
    copy_profile(src_dir, dst_dir, args.rsync, args.rsync_args or "")

    # Update INIs (strict writer + formatting validation)
    update_profiles_ini(dst_app, dst_path_str, make_default=True, create_if_missing=True)
    update_or_create_installs_ini(dst_app, dst_path_str)

    info("Done.")
    if created_new:
        info("(A new destination profile was created and set as default.)")
    else:
        info("(Migrated into the existing default destination profile.)")


if __name__ == "__main__":
    main()
