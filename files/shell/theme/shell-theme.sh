#!/usr/bin/env bash
# shell-theme — switch the terminal palette and the prompt between two variants.
#
# The variants live in @THEME_ROOT@/{v1,v2}: `kitty.conf` holds the sixteen
# ANSI slots, `prompt.zsh` the p10k colour variables. v1 is the previous table
# (256-colour indexes through kitty's extended palette), v2 is the neg.nvim
# roles as truecolor. files/shell/theme/v2/kitty.conf documents the mapping.
#
# The switch is one symlink plus a live kitty reload: files/kitty/theme.conf
# includes ~/.local/state/shell-theme/current/kitty.conf after the v1 default,
# and .zshrc sources the same directory's prompt.zsh. kitty takes the new
# palette immediately (`kitty @ set-colors`); zsh takes it in a new shell.
#
# Usage:
#   shell-theme            print the active variant
#   shell-theme v2         switch to v2 (shorthand for `use v2`)
#   shell-theme use v1|v2  switch explicitly
#   shell-theme list       print the available variants
set -euo pipefail

theme_root=@THEME_ROOT@
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/shell-theme"
current="$state_dir/current"
kitty_shim="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/theme.conf"

die() {
  printf 'shell-theme: %s\n' "$*" >&2
  exit 1
}

variants() {
  find "$theme_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2> /dev/null | sort
}

active() {
  if [ -L "$current" ]; then
    basename "$(readlink "$current")"
  else
    printf 'v1\n'
  fi
}

reload_kitty() {
  # No `pgrep -x kitty`: kitty renames its process to `.kitty-wrapped`, and the
  # remote-control socket only exists inside a kitty session, so the command
  # itself is the test. The shim check matters: `set-colors <missing file>`
  # applies an empty spec, i.e. resets the running windows to kitty defaults.
  if [ ! -r "$kitty_shim" ]; then
    printf 'kitty: %s is missing, palette applies on the next start\n' "$kitty_shim" >&2
    return 0
  fi
  if out=$(kitty @ set-colors --all --configured "$kitty_shim" 2>&1); then
    printf 'kitty: palette applied to the running windows\n'
  else
    printf 'kitty: live reload not applied (%s)\n' "${out:-no running instance}" >&2
    printf 'kitty: the palette applies on the next start\n' >&2
  fi
}

case "${1:-}" in
  '' | status | current)
    active
    ;;
  list | variants)
    variants
    ;;
  use | v1 | v2)
    if [ "$1" = use ]; then
      variant="${2:-}"
    else
      variant="$1"
    fi
    [ -n "$variant" ] || die 'usage: shell-theme use v1|v2'
    [ -d "$theme_root/$variant" ] || die "unknown variant '$variant' (have: $(variants | tr '\n' ' '))"
    mkdir -p "$state_dir"
    ln -sfn "$theme_root/$variant" "$current.tmp"
    mv -T "$current.tmp" "$current"
    printf 'variant: %s\n' "$variant"
    reload_kitty
    # shellcheck disable=SC2016  # the backticks are instructions, not a command
    printf 'zsh: new shells get the prompt; run `exec zsh` in this one\n'
    ;;
  -h | --help | help)
    sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    die "unknown argument '$1' (try: shell-theme help)"
    ;;
esac
