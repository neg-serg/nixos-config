#!/usr/bin/env bash
set -euo pipefail

# Session-format regression gate for the dsh package patches.
#
# Decodes every stored Session artifact through dsh's own format catalog (the
# v0->v3 migration chain) and fails when any of them no longer migrates. See
# packages/dsh/patch-session-format.py for the compatibility patches this guards.
#
# Usage: check-dsh-sessions.sh [dsh-store-path] [sessions-root]
#
# Without an argument the dsh store path is taken from the running
# dsh.service unit, then from the `dsh` wrapper on PATH.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

resolve_dsh() {
  local path=""
  path="$(systemctl --user show -p ExecStart --value dsh.service 2>/dev/null |
    grep -o '/nix/store/[a-z0-9]*-dsh-[0-9][^/]*' | head -n1 || true)"
  if [[ -z "$path" ]]; then
    path="$(command -v dsh 2>/dev/null | xargs -r grep -oh '/nix/store/[a-z0-9]*-dsh-[0-9][^/]*' 2>/dev/null | head -n1 || true)"
  fi
  printf '%s' "$path"
}

dsh_path="${1:-$(resolve_dsh)}"
if [[ -z "$dsh_path" ]]; then
  echo "check-dsh-sessions: cannot resolve a dsh store path — pass one explicitly" >&2
  exit 2
fi

exec node "$script_dir/check-dsh-sessions.mjs" "$dsh_path" "${@:2}"
