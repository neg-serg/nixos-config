#!/usr/bin/env bash
set -euo pipefail

# LustyExplorer (files/nvim/lua/lusty) headless regression smoke test.
# Runs the deployed logic from the repo tree with a clean nvim, so neither
# the deployed config copy nor plugins can shadow the tested modules.

repo_root="$(git rev-parse --show-toplevel 2> /dev/null || pwd)"
cd "$repo_root"

if ! command -v nvim > /dev/null 2>&1; then
  echo "check-lusty-smoke: nvim not found, skipping" >&2
  exit 0
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

# All headless suites: the Lua-port smoke plus the native float suites
# (native_pick pickers and the serve-backed filesystem picker).
suites=(
  files/nvim/lua/lusty/tests/smoke.lua
  files/nvim/lua/lusty/tests/native_float_smoke.lua
  files/nvim/lua/lusty/tests/filesystem_float_smoke.lua
  files/nvim/lua/lusty/tests/filesystem_float_icons_smoke.lua
  files/nvim/lua/lusty/tests/filesystem_float_dirs_rev_smoke.lua
  files/nvim/lua/lusty/tests/filesystem_float_special_smoke.lua
  files/nvim/lua/lusty/tests/filesystem_float_marks_smoke.lua
  files/nvim/lua/lusty/tests/filesystem_float_frecency_smoke.lua
  files/nvim/lua/lusty/tests/filesystem_float_create_smoke.lua
  files/nvim/lua/lusty/tests/filesystem_float_depth_smoke.lua
  files/nvim/lua/lusty/tests/filesystem_float_preview_smoke.lua
  files/nvim/lua/lusty/tests/tables_parity_smoke.lua
)
for suite in "${suites[@]}"; do
  if ! nvim --clean --headless -l "$suite" > "$log" 2>&1; then
    cat "$log" >&2
    exit 1
  fi
done
