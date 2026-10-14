#!/usr/bin/env bash
# One-time (idempotent) relocation of the dsh home into XDG directories.
#
# dsh itself knows only one root ($DSH_HOME, default ~/.dsh) and dsh-TUI keeps
# its preferences in ~/.dsh-tui, so the split is done with symlinks:
#
#   ~/.local/share/dsh   profiles, skills, storages, attachments, secrets, db
#   ~/.config/dsh        settings.yaml, cordis.patch.yml (user-owned config)
#   ~/.local/state/dsh   sessions/, tui/ (the old ~/.dsh-tui)
#   ~/.cache/dsh         cache/
#   ~/.dsh     -> ~/.local/share/dsh      (compat: hardcoded paths keep working)
#   ~/.dsh-tui -> ~/.local/state/dsh/tui
#
# The wrapper (modules/user/nix-maid/apps/dsh.nix) exports DSH_HOME only once
# the data directory exists, so a partial migration never points dsh at an
# empty home. Safe to re-run; --dry-run prints the actions only.
set -euo pipefail

dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

log() { printf 'dsh-xdg-migrate: %s\n' "$*"; }

run() {
  if [ "$dry_run" = 1 ]; then
    printf 'dsh-xdg-migrate: [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

home="${HOME:?}"
data="${XDG_DATA_HOME:-$home/.local/share}/dsh"
config="${XDG_CONFIG_HOME:-$home/.config}/dsh"
state="${XDG_STATE_HOME:-$home/.local/state}/dsh"
cache="${XDG_CACHE_HOME:-$home/.cache}/dsh"
legacy="$home/.dsh"
legacy_tui="$home/.dsh-tui"

# Move a path out of the legacy home, never clobbering an existing target:
# if both sides exist the legacy copy is left in place for a manual merge.
move_path() {
  src=$1 dst=$2
  [ -e "$src" ] || return 0
  if [ -e "$dst" ]; then
    log "both $src and $dst exist — left $src in place (merge by hand)"
    return 0
  fi
  run mkdir -p "$(dirname "$dst")"
  if [ "$dry_run" = 1 ]; then
    log "[dry-run] move $src -> $dst"
  else
    mv "$src" "$dst"
    log "moved $src -> $dst"
  fi
}

# Create the compatibility symlink only when the target really exists, so a
# partial migration neither dangles nor replaces a real directory.
symlink_to() {
  target=$1 linkpath=$2
  if [ ! -e "$target" ]; then
    log "skip link: $target does not exist yet"
    return 0
  fi
  if [ -L "$linkpath" ] && [ "$(readlink -f "$linkpath")" = "$(readlink -f "$target")" ]; then
    return 0
  fi
  run mkdir -p "$(dirname "$linkpath")"
  run ln -sfn "$target" "$linkpath"
  if [ "$dry_run" = 1 ]; then
    log "[dry-run] link $linkpath -> $target"
  else
    log "$linkpath -> $target"
  fi
}

# 1. The home itself.
if [ -d "$legacy" ] && [ ! -L "$legacy" ]; then
  move_path "$legacy" "$data"
fi
if [ -d "$legacy" ] && [ ! -L "$legacy" ]; then
  log "legacy home is still a real directory — not linking over it"
else
  symlink_to "$data" "$legacy"
fi

# 2. Subtrees that belong to state and cache.
for pair in "cache=$cache" "sessions=$state/sessions"; do
  name=${pair%%=*}
  dst=${pair#*=}
  if [ -d "$data/$name" ] && [ ! -L "$data/$name" ]; then
    move_path "$data/$name" "$dst"
    symlink_to "$dst" "$data/$name"
  fi
done

# 3. User-owned config files (dsh-models keeps patching them; the symlink makes
#    $DSH_HOME/<file> and ~/.config/dsh/<file> the same file).
for f in settings.yaml cordis.patch.yml; do
  if [ -f "$data/$f" ] && [ ! -L "$data/$f" ]; then
    if [ -e "$config/$f" ]; then
      log "both $data/$f and $config/$f exist — keeping the config copy"
    else
      move_path "$data/$f" "$config/$f"
      symlink_to "$config/$f" "$data/$f"
    fi
  fi
done

# 4. dsh-TUI preferences.
if [ -d "$legacy_tui" ] && [ ! -L "$legacy_tui" ]; then
  move_path "$legacy_tui" "$state/tui"
fi
if [ -d "$legacy_tui" ] && [ ! -L "$legacy_tui" ]; then
  log "legacy ~/.dsh-tui is still a real directory — not linking over it"
else
  symlink_to "$state/tui" "$legacy_tui"
fi

log "done (data=$data config=$config state=$state cache=$cache)"
