#!/bin/sh
# List the worktrees of the checkout in the Herdr action context.
#
# `dsh-worktree list` prints and exits, and a plugin popup closes with its
# command, so the output is held until the user dismisses it.
set -eu

ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"
dir=""
if [ -n "$ctx" ] && command -v jq > /dev/null 2>&1; then
  dir="$(printf '%s' "$ctx" | jq -r '.focused_pane_cwd // .workspace_cwd // empty')"
fi
if [ -n "$dir" ]; then
  cd "$dir"
fi

# The popup runs a login shell, but the helper lives in ~/.local/bin — resolve
# it explicitly so a stripped PATH still finds it.
helper="$(command -v dsh-worktree 2> /dev/null || true)"
[ -n "$helper" ] || helper="$HOME/.local/bin/dsh-worktree"
if [ ! -x "$helper" ]; then
  printf 'dsh-worktree: helper not found\n'
  read -r _ || true
  exit 1
fi

out="$("$helper" list || true)"
if [ -z "$out" ]; then
  printf 'no worktrees for %s\n' "$(pwd)"
else
  printf '%s\n' "$out"
fi
printf '\npress enter to close\n'
read -r _ || true
