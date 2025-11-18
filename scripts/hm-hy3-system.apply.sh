#!/usr/bin/env bash
set -euo pipefail

# Switch Home‑Manager to use the system hy3 plugin and remove the hy3 flake input.
# Usage: scripts/hm-hy3-system.apply.sh [PATH_TO_HM_REPO]
# Default path: /etc/nixos/home (falls back to ~/.dotfiles/nix/.config/home-manager)

default_repo="/etc/nixos/home"
fallback_repo="$HOME/.dotfiles/nix/.config/home-manager"
if [ ! -d "$default_repo" ]; then
  default_repo="$fallback_repo"
fi
repo="${1:-$default_repo}"

fail() {
  echo "[ERR] $*" >&2
  exit 1
}
msg() { echo "[OK ] $*"; }

[ -d "$repo" ] || fail "Repo not found: $repo"

fn() { printf '%s' "$repo/$1"; }

req_files=(
  flake.nix
  flake/mkHMArgs.nix
  flake/pkgs-extras.nix
  modules/user/gui/hyprland/core.nix
)

for f in "${req_files[@]}"; do
  [ -f "$(fn "$f")" ] || fail "Missing file: $repo/$f"
done

backup_dir="$repo/.backup-hy3-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_dir"
for f in "${req_files[@]}"; do
  install -Dm0644 "$(fn "$f")" "$backup_dir/$f"
done
msg "Backups saved under $backup_dir"

# 1) flake.nix — drop hy3 input, stop threading it, and keep extras sane
perl -0777 -i -pe '
  s/\n\s*# Pin hy3 to tag compatible with Hyprland v0\.52\.x\n\s*hy3\s*=\s*\{\n\s*# hy3 tags track Hyprland compatibility \(hlX\.Y\.Z\)\n\s*url\s*=\s*"github:outfoxxed\/hy3\?ref=[^"]+";[^\n]*\n\s*# Ensure hy3 uses the same Hyprland input we pin below\n\s*inputs\.hyprland\.follows\s*=\s*"hyprland";\n\s*\};\n//ms;
  s/^\s*hy3,\s*\n//m;
  s/\binherit\s+lib\s+perSystem\s+hy3\s+yandexBrowserInput\s+nur\s+inputs;/inherit lib perSystem yandexBrowserInput nur inputs;/;
  s/\binherit\s+hy3\s+pkgs\s+system;/inherit pkgs system;/;
' "$(fn flake.nix)"
msg "Patched flake.nix"

# 2) flake/mkHMArgs.nix — remove hy3 arg; provide a stub so modules can accept it
perl -0777 -i -pe '
  s/\n\s*hy3,\n/\n/;
  s/\binherit\s+hy3;/hy3 = {};/;
' "$(fn flake/mkHMArgs.nix)"
msg "Patched flake/mkHMArgs.nix"

# 3) flake/pkgs-extras.nix — use system plugin package instead of hy3 input
perl -0777 -i -pe '
  s/\n\s*hy3,\n/\n/;
  s/hy3\.packages\.\$\{system\}\.hy3/pkgs.hyprlandPlugins.hy3/;
' "$(fn flake/pkgs-extras.nix)"
msg "Patched flake/pkgs-extras.nix"

# 4) modules/user/gui/hyprland/core.nix — load plugin from /etc/hypr/libhy3.so and stop using hy3 input
perl -0777 -i -pe '
  # Drop hy3 from arg list (keep spacing tidy)
  s/\n\s*hy3,\s*# flake input \(passed via mkHMArgs\) to locate hy3 plugin path\n/\n/;
  # Replace dynamic plugin path with system path
  s/let\s+[^;]*pluginPath\s*=\s*"[^"]*";\s*in\s*xdg\.mkXdgText\s*"hypr\/plugins\.conf"/xdg.mkXdgText "hypr\/plugins.conf"/s;
  s/plugin\s*=\s*\$\{pluginPath\}/plugin = \/etc\/hypr\/libhy3.so/;
  # Remove the keep-alive home.packages for hy3
  s/\n\s*\(mkIf\s*\(config\.features\.gui\.hy3\.enable[^)]*\)\s*\{\s*home\.packages\s*=\s*\[\s*\(hy3\.packages\.[^]]*\)\s*\];\s*\}\s*\)\n/\n/s;
' "$(fn modules/user/gui/hyprland/core.nix)"
msg "Patched modules/user/gui/hyprland/core.nix"

cat << EOF

Done.
Next steps:
  1) Update lock:   (cd "$repo" && nix flake lock)
  2) Apply HM:      (cd "$repo" && seh)   # or: home-manager switch --flake "$repo"

Verification:
  - ~/.config/hypr/plugins.conf should contain:  plugin = /etc/hypr/libhy3.so
  - /etc/hypr/libhy3.so should exist (provided by NixOS config)
  - Hyprland version: Hyprland --version

If something looks off, your originals are backed up under:
  $backup_dir

EOF
