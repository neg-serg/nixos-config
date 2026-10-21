#!/bin/sh
# Prompt for a worktree name and hand off to dsh-worktree.
#
# Runs inside a Herdr plugin popup: the working directory is the plugin root,
# not the checkout, so the checkout comes from the action context Herdr exports
# (focused pane first, workspace second). `dsh-worktree new` then opens the tree
# as a workspace of its own and starts a dsh session in it.
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

# A popup closes as soon as its command exits, so a failure has to be held on
# screen — otherwise the error flashes by.
hold() {
  printf '\n%s\npress enter to close\n' "$1"
  read -r _ || true
}

printf 'worktree name: '
read -r name || exit 1
if [ -z "$name" ]; then
  hold 'no name given'
  exit 1
fi

"$helper" new "$name" --open herdr || hold 'dsh-worktree failed'
