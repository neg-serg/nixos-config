#!/usr/bin/env bash
# Set up RollerCoaster Tycoon Classic (Steam app 683900) on a system that
# deliberately ships no 32-bit graphics stack: the game is a 32-bit PE, wine
# needs a 32-bit GL driver, and this host only carries i686 glibc + libglvnd in
# the Steam sandbox (see modules/user/games/launchers.nix).
#
# Both pieces stay outside the system closure:
#   1. pkgsi686Linux.mesa is built into the user GC root
#      ~/.local/state/rct32-mesa (llvmpipe and wined3d need nothing else);
#   2. the per-app launch options point Mesa at that root.
#
# Steam must be closed: it rewrites localconfig.vdf on exit and would drop the
# edit. Run through `just rct32-setup`.
set -euo pipefail

if pgrep -f 'steamrt64/steam|/steam\.sh' > /dev/null 2>&1; then
  echo "steam-rct32: close Steam first (it rewrites localconfig.vdf on exit)" >&2
  exit 1
fi

nix build --out-link "$HOME/.local/state/rct32-mesa" "nixpkgs#pkgsi686Linux.mesa"

# $HOME stays literal here on purpose: Steam runs launch options through
# /bin/sh -c inside the game sandbox, where HOME is still the real home.
launch_options='LD_LIBRARY_PATH=$HOME/.local/state/rct32-mesa/lib LIBGL_DRIVERS_PATH=$HOME/.local/state/rct32-mesa/lib/dri MESA_LOADER_DRIVER_OVERRIDE=llvmpipe LIBGL_ALWAYS_SOFTWARE=1 PROTON_USE_WINED3D=1 %command%'

LAUNCH_OPTIONS="$launch_options" python3 - << 'PY'
import glob
import os
import sys

options = os.environ["LAUNCH_OPTIONS"]
files = glob.glob(
    os.path.join(os.environ["HOME"], ".local/share/Steam/userdata/*/config/localconfig.vdf")
)
if not files:
    sys.exit("steam-rct32: no Steam userdata found; run Steam once first")

key = '\t\t\t\t\t"683900"\n\t\t\t\t\t{\n'
line = '\t\t\t\t\t\t"LaunchOptions"\t\t"' + options + '"'
changed = 0
for path in files:
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if text.count(key) != 1:  # this account has no RCT Classic entry
        continue
    start = text.index(key) + len(key)
    end = text.find("\n\t\t\t\t\t}\n", start)
    if end < 0:
        sys.exit(f"steam-rct32: unterminated 683900 block in {path}")
    block = text[start:end]
    lines = block.split("\n")
    # Idempotent: replace an existing entry, otherwise add it at the top.
    if any(l.strip().startswith('"LaunchOptions"') for l in lines):
        lines = [
            line if l.strip().startswith('"LaunchOptions"') else l for l in lines
        ]
    else:
        lines = [line] + lines
    backup = path + ".rct32.bak"
    if not os.path.exists(backup):
        with open(backup, "w", encoding="utf-8") as f:
            f.write(text)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text[:start] + "\n".join(lines) + text[end:])
    changed += 1

if changed == 0:
    sys.exit("steam-rct32: no Steam account has app 683900 installed")
print(f"steam-rct32: patched {changed} Steam account(s)")
PY

echo "steam-rct32: done; launch RCT Classic from Steam (app 683900)"
