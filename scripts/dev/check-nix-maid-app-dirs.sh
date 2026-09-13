#!/usr/bin/env bash
# Verify the nix-maid apps auto-import contract.
#
# modules/user/nix-maid/apps/default.nix imports every sibling .nix file and
# every sibling directory that carries its own default.nix, via
# `neg.importDir { includeDirs = true; }`. Directory import is therefore
# opt-in per subdirectory: data and plugin-bundle directories (dsh-*, assets,
# presets) need no deny-list and cannot break evaluation with:
#
#   error: Path 'modules/user/nix-maid/apps/<name>/default.nix'
#          does not exist in Git repository "/etc/nixos"
#
# This guard pins that contract. It fails if default.nix stops using
# importDir/includeDirs (a hand-rolled `builtins.readDir` filter imports every
# entry) and if lib/neg-helpers.nix drops the default.nix existence check that
# makes the skip safe. The directories currently skipped are listed for
# visibility so a module that lost its default.nix does not disappear silently.
#
# Usage: check-nix-maid-app-dirs.sh [apps-dir] [neg-helpers.nix]
#   defaults: <repo-root>/modules/user/nix-maid/apps,
#             <repo-root>/lib/neg-helpers.nix

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2> /dev/null || pwd)"

APPS_DIR="${1:-$REPO_ROOT/modules/user/nix-maid/apps}"
HELPERS="${2:-$REPO_ROOT/lib/neg-helpers.nix}"
DEFAULT_NIX="$APPS_DIR/default.nix"

for path in "$APPS_DIR" "$DEFAULT_NIX" "$HELPERS"; do
  if [[ ! -e "$path" ]]; then
    echo "missing required path: $path" >&2
    exit 1
  fi
done

echo "Checking nix-maid app auto-import contract..."

if ! grep -qE 'neg\.importDir' "$DEFAULT_NIX"; then
  echo "FAIL: $DEFAULT_NIX does not call neg.importDir." >&2
  echo "      A hand-rolled builtins.readDir filter imports every entry, so any" >&2
  echo "      directory without default.nix breaks the next system evaluation." >&2
  exit 1
fi

if ! grep -qE 'includeDirs[[:space:]]*=[[:space:]]*true' "$DEFAULT_NIX"; then
  echo "FAIL: $DEFAULT_NIX does not set includeDirs = true — sibling module" >&2
  echo "      directories would stop being imported." >&2
  exit 1
fi

# The automatic skip is only safe while importDir requires a default.nix before
# treating a directory as a module.
if ! grep -qE 'isModuleDir' "$HELPERS" || ! grep -qE 'pathExists.*default\.nix' "$HELPERS"; then
  echo "FAIL: $HELPERS no longer gates directory import on default.nix existence" >&2
  echo "      (expected isModuleDir + builtins.pathExists .../default.nix)." >&2
  exit 1
fi

shopt -s nullglob dotglob

modules=0
skipped=()
for path in "$APPS_DIR"/*/; do
  if [[ -f "$path/default.nix" ]]; then
    modules=$((modules + 1))
  else
    skipped+=("$(basename "$path")")
  fi
done

echo "OK: importDir contract intact; $modules directory(ies) imported, ${#skipped[@]} data directory(ies) skipped automatically"
if ((${#skipped[@]} > 0)); then
  echo "    skipped (no default.nix): ${skipped[*]}"
fi
