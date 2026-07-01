#!/usr/bin/env bash
# diff-preview: build new system closure and show diff vs current
# Usage: scripts/dev/diff-preview.sh [host] [--new-only] [--keep-result]

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HOST="telfir"
NEW_ONLY=false
KEEP_RESULT=false

for arg in "$@"; do
  case "$arg" in
    --new-only) NEW_ONLY=true ;;
    --keep-result) KEEP_RESULT=true ;;
    -h|--help)
      sed -n '2,3p' "$0" | sed 's/^# *//'
      echo ""
      echo "Arguments:"
      echo "  host          Hostname to build (default: telfir)"
      echo "  --new-only    Show only newly added packages"
      echo "  --keep-result Keep result symlink after diff"
      exit 0
      ;;
    *)
      if [ "${arg:0:1}" != "-" ]; then
        HOST="$arg"
      fi
      ;;
  esac
done

if ! command -v nvd >/dev/null 2>&1; then
  echo "diff-preview: nvd not found. Install it or use: nix run nixpkgs#nvd"
  exit 1
fi

OUT_LINK="${REPO_ROOT}/result"

echo "==> Building system closure for host '${HOST}'..."
nix build ".#nixosConfigurations.${HOST}.config.system.build.toplevel" \
  --out-link "$OUT_LINK" \
  --option connect-timeout 60 \
  --option download-attempts 2 \
  --option stalled-download-timeout 600

echo ""
echo "==> Diff: current-system vs new build"
echo ""

if [ "$NEW_ONLY" = true ]; then
  nvd diff /run/current-system "$OUT_LINK" 2>&1 | awk '/^Added packages:/{flag=1} flag'
else
  nvd diff /run/current-system "$OUT_LINK"
fi

if [ "$KEEP_RESULT" = false ]; then
  rm -f "$OUT_LINK"
fi
