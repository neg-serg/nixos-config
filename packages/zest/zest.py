#!/usr/bin/env python3
"""zest — CLI for ZestBay plugin management (LV2/CLAP/VST3 host in distrobox).

Commands:
  zest list                list available plugins (URI<TAB>name) from the container
  zest add <uri>           add a plugin instance (persisted in plugins.json)
  zest rm <uri|name>       remove plugin instance(s) matching uri or display name
  zest ls                  show current plugin instances
  zest status              show whether ZestBay is running

Config lives in ~/.config/zestbay/ (shared host home). ZestBay is restarted
after add/rm so it loads the change; if the zestbay systemd user service is
not present yet, it falls back to pkill + detached relaunch.
"""
import base64
import json
import os
import re
import subprocess
import sys

CONFIG = os.path.expanduser("~/.config/zestbay/plugins.json")
CONTAINER = "arch-zestbay"

# Python snippet run INSIDE the container: scan /usr/lib/lv2 manifests.
# manifest.ttl declares each plugin + points to a seeAlso ttl where the
# doap:name lives; follow the reference to get readable names.
LIST_PY = r"""
import glob, os, re
out = []
for m in glob.glob('/usr/lib/lv2/*/manifest.ttl'):
    d = os.path.dirname(m)
    txt = open(m, encoding='utf-8', errors='replace').read()
    for para in txt.split('\n\n'):
        pm = re.search(r'<([^>]+)>\s+a\s+lv2:Plugin\b', para)
        if not pm:
            continue
        uri = pm.group(1)
        name = None
        sa = re.search(r'rdfs:seeAlso\s+<([^>]+)>', para)
        if sa:
            try:
                extra = open(os.path.join(d, sa.group(1)),
                             encoding='utf-8', errors='replace').read()
                nm = re.search(r'doap:name\s+"([^"]+)"', extra)
                if nm:
                    name = nm.group(1)
            except OSError:
                pass
        out.append((uri, name if name else uri))
for u, n in sorted(out):
    print(u + '\t' + n)
"""


def in_container(cmd):
    return subprocess.run(
        ["distrobox-enter", CONTAINER, "--", "bash", "-lc", cmd],
        capture_output=True,
        text=True,
    )


def available_plugins():
    """dict uri -> display name, from LV2 manifests inside the container."""
    b64 = base64.b64encode(LIST_PY.encode()).decode()
    r = in_container(f"echo {b64} | base64 -d | python3")
    if r.returncode != 0:
        print("failed to list plugins:", r.stderr, file=sys.stderr)
        sys.exit(1)
    out = {}
    for line in r.stdout.splitlines():
        if "\t" in line:
            uri, name = line.split("\t", 1)
            out[uri] = name
    return out


def load_plugins():
    if not os.path.exists(CONFIG):
        return []
    try:
        with open(CONFIG) as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return []


def save_plugins(plugins):
    os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
    with open(CONFIG, "w") as f:
        json.dump(plugins, f, indent=2)
        f.write("\n")


def service_exists():
    r = subprocess.run(
        ["systemctl", "--user", "list-unit-files", "zestbay.service"],
        capture_output=True,
        text=True,
    )
    return "zestbay.service" in r.stdout


def stop_zestbay():
    if service_exists():
        subprocess.run(
            ["systemctl", "--user", "stop", "zestbay.service"],
            capture_output=True,
        )
    else:
        in_container(
            "pkill -x zestbay; sleep 0.5; pkill -x zestbay 2>/dev/null; true"
        )


def start_zestbay():
    if service_exists():
        subprocess.run(
            ["systemctl", "--user", "start", "zestbay.service"],
            capture_output=True,
        )
    else:
        # detached relaunch inside the container
        subprocess.Popen(
            [
                "distrobox-enter",
                CONTAINER,
                "--",
                "bash",
                "-lc",
                "nohup zestbay >/dev/null 2>&1 & disown; sleep 0.2",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def restart_zestbay():
    stop_zestbay()
    start_zestbay()


def cmd_list(_):
    for uri, name in sorted(available_plugins().items()):
        print(f"{name}\t{uri}")


def cmd_add(args):
    if not args:
        print("usage: zest add <uri>", file=sys.stderr)
        sys.exit(2)
    uri = args[0]
    available = available_plugins()
    if uri not in available:
        print(
            f"unknown plugin: {uri}\n(zest list to see URIs)", file=sys.stderr
        )
        sys.exit(1)
    plugins = load_plugins()
    if any(p.get("uri") == uri for p in plugins):
        print(f"already present: {uri}")
        return
    plugins.append({"uri": uri, "display_name": available[uri]})
    restart_zestbay()
    save_plugins(plugins)
    print(f"added: {available[uri]} ({uri})")


def cmd_rm(args):
    if not args:
        print("usage: zest rm <uri|name>", file=sys.stderr)
        sys.exit(2)
    pat = args[0]
    plugins = load_plugins()
    kept, removed = [], []
    for p in plugins:
        if pat in p.get("uri", "") or pat in p.get("display_name", ""):
            removed.append(p)
        else:
            kept.append(p)
    if not removed:
        print("no matching plugin instances", file=sys.stderr)
        sys.exit(1)
    restart_zestbay()
    save_plugins(kept)
    for p in removed:
        print(f"removed: {p.get('display_name')} ({p.get('uri')})")


def cmd_ls(_):
    plugins = load_plugins()
    if not plugins:
        print("(no plugin instances in plugins.json)")
        return
    for p in plugins:
        print(f"{p.get('display_name', '?')}\t{p.get('uri', '?')}")


def cmd_status(_):
    r = in_container(
        "pgrep -x zestbay >/dev/null && echo running || echo stopped"
    )
    print("zestbay:", r.stdout.strip())


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    cmd, args = sys.argv[1], sys.argv[2:]
    table = {
        "list": cmd_list,
        "add": cmd_add,
        "rm": cmd_rm,
        "ls": cmd_ls,
        "status": cmd_status,
    }
    if cmd not in table:
        print(f"unknown command: {cmd}\n{__doc__}", file=sys.stderr)
        sys.exit(2)
    table[cmd](args)


if __name__ == "__main__":
    main()
