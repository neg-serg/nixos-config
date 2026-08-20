#!/usr/bin/env python3
"""carlactl — console controller for routing external VSTs through headless Carla.

On this host Carla is built JACK-only (no native PipeWire), so everything runs
under pw-jack with LD_LIBRARY_PATH=/run/current-system/sw/lib (PipeWire's
libjack). Carla's headless mode requires a .carxp project file, which we
generate programmatically via Carla's C API — no GUI, no manual authoring.

Commands:
  carlactl list [--format f]     scan installed plugins -> "format<TAB>name<TAB>maker" lines
  carlactl run [TYPE:NAME|PATH]  generate .carxp + launch headless (no arg: fzf)
  carlactl stop                  stop the running Carla
  carlactl status                engine pid, JACK ports, links
  carlactl route [mix|an|aes|spdif|phones|none]  route Carla audio-out
  carlactl projects [NAME]       list/saved .carxp projects, launch via fzf
"""
import os
import sys
import glob
import json
import signal
import subprocess
import time
from pathlib import Path

# --- locations (provided by the Nix wrapper) ---------------------------------
CARLA_SHARE = os.environ.get("CARLA_SHARE_DIR", "")
CARLA_LIB = os.environ.get("CARLA_LIB_DIR", "")
STDLIB = os.path.join(CARLA_LIB, "libcarla_standalone2.so")
STATE = Path.home() / ".local/state/carlactl"
PROJECTS = STATE / "projects"
PIDFILE = STATE / "carla.pid"
LOGFILE = STATE / "carla.log"
CACHE = STATE / "plugins.json"
CACHE_VERSION = 2  # bump when the cached plugin info format changes

# Plugin format -> (scan root suffix, discovery type, glob pattern)
FORMATS = {
    "vst3": ("vst3", "vst3", "*.vst3"),
    "vst2": ("vst", "vst2", "*.so"),
    "lv2": (
        "lv2",
        "lv2",
        "*.lv2",
    ),  # bundle dirs only (one dir = many plugins)
    "clap": ("clap", "clap", "*.clap"),
}

# Default scan: VST2/VST3 (Carla discovery supports these). LV2 is bundle-based
# and CLAP is unsupported by carla-discovery-native; both stay opt-in via
# '--format', with LV2 handled by ZestBay/zest for day-to-day use.
DEFAULT_FORMATS = ("vst3", "vst2")

# RME HDSPe AIO Pro output pairs (same mapping as pwroute).
ROUTES = {
    "mix": ("playback_FL", "playback_FR"),  # shared sink (MPD+SuperDirt+Carla)
    "an": ("playback_AUX0", "playback_AUX1"),
    "aes": ("playback_AUX2", "playback_AUX3"),
    "spdif": ("playback_AUX4", "playback_AUX5"),
    "phones": ("playback_AUX6", "playback_AUX7"),
}


def sh(args, **kw):
    return subprocess.run(args, text=True, capture_output=True, **kw)


def scan_roots(fmt):
    """Plugin dirs, mirroring environment.nix's makePluginPath search path."""
    suffix, _, _ = FORMATS[fmt]
    home = str(Path.home())
    user = os.environ.get("USER", "neg")
    roots = [
        f"/run/current-system/sw/lib/{suffix}",
        f"/etc/profiles/per-user/{user}/lib/{suffix}",
        f"{home}/.local/state/nix/profile/lib/{suffix}",
        f"{home}/.{suffix}",
    ]
    if fmt == "vst2":
        roots += ["/run/current-system/sw/lib/lxvst", f"{home}/.lxvst"]
    return [r for r in dict.fromkeys(roots) if os.path.isdir(r)]


def _plugin_name(path, fmt):
    """Derive a plugin name from its bundle/file name (fast, no discovery).

    carla-discovery-native is slow on multi-plugin mega-bundles (lsp-plugins
    enumerates ~100 plugins), so listing uses the filename instead. This is
    exact for single-plugin bundles (Vital.vst3 -> Vital), which is what VST
    routing cares about.
    """
    base = os.path.basename(path.rstrip("/"))
    suffix = FORMATS[fmt][0]
    if base.endswith(f".{suffix}"):
        return base[: -len(f".{suffix}")]
    if base.endswith(".so"):
        return base[:-3]
    return base


def scan_plugins(formats=DEFAULT_FORMATS):
    """Yield plugin info dicts (filename-derived, fast). Dedupe by (format, name)."""
    seen = set()
    for fmt in formats:
        _, _, pattern = FORMATS[fmt]
        for root in scan_roots(fmt):
            hits = glob.glob(os.path.join(root, "**", pattern), recursive=True)
            for p in hits:
                if fmt == "vst2" and not p.endswith(".so"):
                    continue
                if fmt == "vst3" and os.path.isfile(p):
                    continue
                name = _plugin_name(p, fmt)
                key = (fmt, name)
                if key in seen:
                    continue
                seen.add(key)
                yield {"format": fmt, "name": name, "path": p, "maker": ""}


def _roots_fingerprint(formats):
    roots = set()
    for fmt in formats:
        roots.update(scan_roots(fmt))
    sig = []
    for r in sorted(roots):
        try:
            sig.append([r, os.path.getmtime(r)])
        except OSError:
            pass
    return sig


def list_plugins(formats=DEFAULT_FORMATS, use_cache=True):
    """Scan plugins, cached on the set+mtime of the scanned roots.

    Scanning every VST2 in lsp-plugins.vst is slow (~100s of .so files), so we
    persist results and only rescan when a plugin dir's mtime changes (e.g. a
    system rebuild).
    """
    fp = _roots_fingerprint(formats)
    if use_cache and CACHE.exists():
        try:
            data = json.loads(CACHE.read_text())
            if data.get("v") == CACHE_VERSION and data.get("fp") == fp:
                return data["plugins"]
        except (OSError, ValueError, KeyError):
            pass
    plugins = sorted(
        scan_plugins(formats), key=lambda i: (i["format"], i["name"])
    )
    if use_cache:
        STATE.mkdir(parents=True, exist_ok=True)
        try:
            CACHE.write_text(
                json.dumps({"v": CACHE_VERSION, "fp": fp, "plugins": plugins})
            )
        except OSError:
            pass
    return plugins


# --- project generation (Carla C API) ---------------------------------------


def gen_project(ptype, plugin_path, name, out_path):
    """Create a .carxp project with one plugin, via libcarla_standalone2."""
    if CARLA_SHARE not in sys.path:
        sys.path.insert(0, CARLA_SHARE)
    import carla_backend as cb

    PLUGIN_TYPE = {
        "vst3": cb.PLUGIN_VST3,
        "vst2": cb.PLUGIN_VST2,
        "lv2": cb.PLUGIN_LV2,
    }
    if ptype not in PLUGIN_TYPE:
        return False, f"unsupported plugin type: {ptype}"
    host = cb.CarlaHostDLL(STDLIB, True)
    if not host.engine_init("JACK", "carlactl"):
        return False, "engine_init failed (is PipeWire running?)"
    ok = host.add_plugin(
        cb.BINARY_NATIVE,
        PLUGIN_TYPE[ptype],
        plugin_path,
        name,
        name,
        0,
        0,
        cb.PLUGIN_OPTIONS_NULL,
    )
    if not ok:
        host.engine_close()
        return False, f"add_plugin failed for {plugin_path}"
    saved = host.save_project(out_path)
    host.engine_close()
    return saved, None if saved else "save_project failed"


def is_yabridge(plugin_path):
    """True if the plugin binary is a yabridge wrapper (.so under a yabridge
    dir). yabridge libs segfault the in-process Carla C API (asio epoll_reactor
    in libyabridge), so those plugins use the frontend .carxp path instead."""
    return "yabridge" in str(plugin_path)


def gen_project_xml(ptype, plugin_path, name, out_path):
    """Write a minimal one-plugin .carxp directly (frontend path).

    Used for yabridge-wrapped Windows plugins: the carla frontend (carla -n)
    loads them fine, while libcarla_standalone2 in-process add_plugin
    segfaults inside libyabridge-vst2.so."""
    type_map = {"vst2": "VST2", "vst3": "VST3", "lv2": "LV2"}
    ptype_xml = type_map.get(ptype, ptype.upper())
    xml = f"""<?xml version='1.0' encoding='UTF-8'?>
<!DOCTYPE CARLA-PROJECT>
<CARLA-PROJECT VERSION='2.5'>
 <EngineSettings>
  <ForceStereo>false</ForceStereo>
  <PreferPluginBridges>false</PreferPluginBridges>
  <PreferUiBridges>true</PreferUiBridges>
  <UIsAlwaysOnTop>true</UIsAlwaysOnTop>
  <MaxParameters>200</MaxParameters>
  <UIBridgesTimeout>4000</UIBridgesTimeout>
 </EngineSettings>
 <Transport>
  <BeatsPerMinute>120</BeatsPerMinute>
 </Transport>
 <Plugin>
  <Info>
   <Type>{ptype_xml}</Type>
   <Name>{name}</Name>
   <Binary>{plugin_path}</Binary>
   <Label>{name}</Label>
  </Info>
  <Data>
   <Active>Yes</Active>
  </Data>
 </Plugin>
</CARLA-PROJECT>
"""
    try:
        out_path.write_text(xml)
        return True, None
    except OSError as exc:
        return False, f"write failed: {exc}"


def gen_env():
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = "/run/current-system/sw/lib"
    # yabridge (nixpkgs build) locates its libs through NIX_PROFILES.
    env.setdefault(
        "NIX_PROFILES",
        "/run/current-system/sw /nix/var/nix/profiles/default /etc/profiles/per-user/neg /home/neg/.local/state/nix/profile",
    )
    return env


# --- process lifecycle ------------------------------------------------------


def carla_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except (OSError, ProcessLookupError):
        return False


def read_pid():
    try:
        return int(PIDFILE.read_text().strip())
    except Exception:
        return None


def launch(carxp):
    STATE.mkdir(parents=True, exist_ok=True)
    log = open(LOGFILE, "w")
    proc = subprocess.Popen(
        ["pw-jack", "carla", "-n", carxp],
        stdout=log,
        stderr=subprocess.STDOUT,
        env=gen_env(),
        start_new_session=True,
    )
    PIDFILE.write_text(str(proc.pid))
    return proc.pid


def stop_carla():
    pid = read_pid()
    if pid and carla_alive(pid):
        try:
            os.killpg(os.getpgid(pid), signal.SIGTERM)
        except Exception:
            os.kill(pid, signal.SIGTERM)
        time.sleep(0.5)
        if carla_alive(pid):
            try:
                os.killpg(os.getpgid(pid), signal.SIGKILL)
            except Exception:
                os.kill(pid, signal.SIGKILL)
    PIDFILE.unlink(missing_ok=True)
    return pid


# --- fzf ---------------------------------------------------------------------


def fzf_pick(items, prompt):
    if not sys.stdin.isatty() and not sys.stdout.isatty():
        return None  # non-interactive: caller must supply an argument
    r = sh(
        ["fzf", "--height=40%", "--layout=reverse", f"--prompt={prompt}> "],
        input="\n".join(items),
    )
    return r.stdout.strip() or None


# --- commands ----------------------------------------------------------------


def cmd_list(args):
    formats = tuple(args.format.split(",")) if args.format else DEFAULT_FORMATS
    for p in list_plugins(formats):
        print(f"{p['format']}\t{p['name']}\t{p.get('maker','')}\t{p['path']}")


def resolve_plugin(arg):
    """Resolve 'TYPE:NAME' or a filesystem path to a plugin info dict."""
    if arg and os.path.exists(arg):
        fmt = "vst3"
        for f in FORMATS:
            if arg.endswith(f".{FORMATS[f][0]}") or (
                f == "vst2" and arg.endswith(".so")
            ):
                fmt = f
                break
        return {
            "format": fmt,
            "name": _plugin_name(arg, fmt),
            "path": arg,
            "maker": "",
        }
    fmt, _, name = (arg or "").partition(":")
    # Fast path: most plugins live in their own bundle named after the plugin,
    # so try <name>.<ext> directly.
    if name:
        for f in (fmt,) if fmt else tuple(FORMATS):
            suffix, _, _ = FORMATS[f]
            for root in scan_roots(f):
                cand = os.path.join(root, f"{name}.{suffix}")
                if os.path.exists(cand):
                    return {
                        "format": f,
                        "name": name,
                        "path": cand,
                        "maker": "",
                    }
    # Fallback: full scan (cached).
    formats = (fmt,) if fmt else DEFAULT_FORMATS
    plugins = list_plugins(formats)
    for p in plugins:
        if p["name"].lower() == name.lower():
            return p

    # Fuzzy: normalize spaces/dashes/underscores/case, then substring match.
    # Lets "Legend HZ" find the "LegendHZ" entry (name comes from the file).
    def norm(s):
        return "".join(c for c in s.lower() if c.isalnum())

    target = norm(name)
    if target:
        for p in plugins:
            pn = norm(p["name"])
            if target == pn or target in pn or pn in target:
                return p
    return None


def cmd_run(args):
    arg = args.plugin
    if not arg:
        items = [
            f"{p['format']}\t{p['name']}\t{p.get('maker','')}"
            for p in list_plugins()
        ]
        pick = fzf_pick(items, "plugin")
        if not pick:
            print(
                "error: no plugin given and not a TTY; use 'carlactl run vst3:Vital'",
                file=sys.stderr,
            )
            return 2
        fmt, name, _ = pick.split("\t")
        info = resolve_plugin(f"{fmt}:{name}")
    else:
        info = resolve_plugin(arg)
    if not info:
        print(f"error: plugin not found: {arg}", file=sys.stderr)
        return 1

    PROJECTS.mkdir(parents=True, exist_ok=True)
    out = PROJECTS / f"{info['name'].replace(' ', '_')}.carxp"
    if is_yabridge(info["path"]):
        ok, err = gen_project_xml(
            info["format"], info["path"], info["name"], out
        )
    else:
        ok, err = gen_project(
            info["format"], info["path"], info["name"], str(out)
        )
    if not ok:
        print(f"error: {err}", file=sys.stderr)
        return 1

    pid = launch(str(out))
    print(
        f"started Carla headless (pid {pid}) with {info['format']}:{info['name']}"
    )
    print(f"project: {out}")
    return 0


def cmd_stop(args):
    pid = stop_carla()
    print(f"stopped Carla (pid {pid})" if pid else "Carla not running")


def cmd_status(args):
    pid = read_pid()
    if pid and carla_alive(pid):
        print(f"Carla: running (pid {pid})")
    else:
        print("Carla: not running")
    r = sh(["pw-link", "-l"])
    lines = [ln for ln in r.stdout.splitlines() if "Carla:" in ln]
    print(
        "\n".join(lines) if lines else "  (no Carla ports in PipeWire graph)"
    )


def hw_out(port):
    """Find the RME output node name for a given playback port suffix.

    RME playback_AUX* ports are sink (input) ports — they appear under
    'pw-link -i', not -o.
    """
    r = sh(["pw-link", "-i"])
    for line in r.stdout.splitlines():
        line = line.strip()
        if line.endswith(port) and "alsa_output" in line:
            return line.split(":")[0]
    return None


def cmd_route(args):
    route = args.route or "mix"
    if route not in ROUTES and route != "none":
        print(
            f"error: unknown route {route} (mix|an|aes|spdif|phones|none)",
            file=sys.stderr,
        )
        return 2
    left, rr = ROUTES.get(route, (None, None))
    # disconnect Carla audio-out first
    sh(["pw-link", "-d", "Carla:output_FL"])
    sh(["pw-link", "-d", "Carla:output_FR"])
    if route == "none":
        print("Carla audio-out disconnected")
        return 0
    if route == "mix":
        for ch, out in (("FL", left), ("FR", rr)):
            r = sh(["pw-link", f"Carla:output_{ch}", f"game-stereo:{out}"])
            if r.returncode != 0:
                print(
                    f"warn: could not connect Carla:output_{ch} -> game-stereo:{out}",
                    file=sys.stderr,
                )
        print("Carla audio-out -> game-stereo (shared mix)")
        return 0
    node = hw_out(left)
    if not node:
        print("error: RME output not found in PipeWire graph", file=sys.stderr)
        return 1
    for ch, out in (("FL", left), ("FR", rr)):
        sh(["pw-link", f"Carla:output_{ch}", f"{node}:{out}"])
    print(f"Carla audio-out -> {route} ({node}:{left}/{rr})")
    return 0


def cmd_projects(args):
    projects = sorted(PROJECTS.glob("*.carxp")) if PROJECTS.is_dir() else []
    if not projects:
        print("no saved projects")
        return 0
    if args.name:
        matches = [
            p for p in projects if p.stem == args.name or args.name in p.stem
        ]
        if not matches:
            print(f"error: no project matching {args.name}", file=sys.stderr)
            return 1
        target = matches[0]
    else:
        pick = fzf_pick([p.stem for p in projects], "project")
        if not pick:
            return 0
        target = PROJECTS / f"{pick}.carxp"
    pid = launch(str(target))
    print(f"started Carla headless (pid {pid}) from {target}")
    return 0


# --- main --------------------------------------------------------------------


def main():
    import argparse

    p = argparse.ArgumentParser(
        prog="carlactl", description=__doc__.splitlines()[0]
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("list", help="scan installed plugins")
    sp.add_argument(
        "--format", help="comma-separated formats (vst3,vst2,lv2,clap)"
    )
    sp.set_defaults(func=cmd_list)

    sp = sub.add_parser("run", help="launch a plugin in headless Carla")
    sp.add_argument("plugin", nargs="?", help="TYPE:NAME or path")
    sp.set_defaults(func=cmd_run)

    sp = sub.add_parser("stop", help="stop Carla")
    sp.set_defaults(func=cmd_stop)

    sp = sub.add_parser("status", help="show engine/ports/links")
    sp.set_defaults(func=cmd_status)

    sp = sub.add_parser("route", help="route Carla audio-out")
    sp.add_argument("route", nargs="?", help="mix|an|aes|spdif|phones|none")
    sp.set_defaults(func=cmd_route)

    sp = sub.add_parser("projects", help="saved .carxp projects")
    sp.add_argument("name", nargs="?", help="project name")
    sp.set_defaults(func=cmd_projects)

    args = p.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
