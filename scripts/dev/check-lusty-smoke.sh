#!/usr/bin/env bash
set -euo pipefail

# LustyExplorer (files/nvim/lua/lusty) headless regression smoke test.
# Runs the deployed logic from the repo tree with a clean nvim, so neither
# the deployed config copy nor plugins can shadow the tested modules.

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

if ! command -v nvim >/dev/null 2>&1; then
  echo "check-lusty-smoke: nvim not found, skipping" >&2
  exit 0
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
if ! nvim --clean --headless -l files/nvim/lua/lusty/tests/smoke.lua >"$log" 2>&1; then
  cat "$log" >&2
  exit 1
fi
