#!/usr/bin/env bash
set -euo pipefail

# LustyExplorer (files/nvim/lua/lusty) headless regression smoke test.
# Runs the deployed logic from the repo tree with a clean nvim, so neither
# the deployed config copy nor plugins can shadow the tested modules.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
REPO_ROOT="$(repo_root)"
cd "$REPO_ROOT"

if ! command -v nvim > /dev/null 2>&1; then
  echo "check-lusty-smoke: nvim not found, skipping" >&2
  exit 0
fi

# All headless suites: the native picker suites (native_pick pickers, the
# serve-backed filesystem picker, the split-window contract, the one-line
# mode) plus the shared-helper and parity checks.
suites=(
  files/nvim/lua/lusty/tests/grep_pattern_smoke.lua
  files/nvim/lua/lusty/tests/native_float_smoke.lua
  files/nvim/lua/lusty/tests/filesystem_split_smoke.lua
  files/nvim/lua/lusty/tests/one_line_smoke.lua
  files/nvim/lua/lusty/tests/filesystem_float_smoke.lua
  files/nvim/lua/lusty/tests/filesystem_float_icons_smoke.lua
  files/nvim/lua/lusty/tests/filesystem_float_dirs_rev_smoke.lua
  files/nvim/lua/lusty/tests/filesystem_float_special_smoke.lua
  files/nvim/lua/lusty/tests/filesystem_float_marks_smoke.lua
  files/nvim/lua/lusty/tests/filesystem_float_frecency_smoke.lua
  files/nvim/lua/lusty/tests/filesystem_float_create_smoke.lua
  files/nvim/lua/lusty/tests/filesystem_float_depth_smoke.lua
  files/nvim/lua/lusty/tests/filesystem_float_dots_smoke.lua
  files/nvim/lua/lusty/tests/filesystem_float_preview_smoke.lua
  files/nvim/lua/lusty/tests/filesystem_float_page_smoke.lua
  files/nvim/lua/lusty/tests/tables_parity_smoke.lua
  files/nvim/lua/lusty/tests/theme_parity_smoke.lua
  files/nvim/lua/lusty/tests/ls_colors_parity_smoke.lua
)
# Worker for pmap: one headless nvim per suite. Every suite uses its own
# /tmp names (suffixed with the suite), so concurrent runs cannot collide; the
# log is printed only for a failure, and pmap replays failures in list order.
lusty_one() {
  local suite=$1 log nvimlog rc=0
  log="$(mktemp)"
  # When $XDG_STATE_HOME/nvim cannot be opened for writing (a read-only HOME,
  # which is what the agent sandbox mounts), nvim falls back to ./nvim.log in
  # its cwd — and this worker starts nvim in the repo root, 18 of them at once.
  # Pin the log to the worker's own temp file so the tree stays clean.
  nvimlog="$(mktemp)"
  NVIM_LOG_FILE="$nvimlog" nvim --clean --headless -l "$suite" > "$log" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'FAILED: %s\n' "$suite"
    cat "$log"
    if [ -s "$nvimlog" ]; then
      printf 'nvim log (%s):\n' "$suite"
      cat "$nvimlog"
    fi
  fi
  rm -f "$log" "$nvimlog"
  return "$rc"
}

if ! pmap -- lusty_one < <(printf '%s\n' "${suites[@]}"); then
  exit 1
fi
