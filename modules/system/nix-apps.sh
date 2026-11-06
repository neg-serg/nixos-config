#!/usr/bin/env bash
# nix-apps — maintainer CLI for the on-demand GC roots.
#
# Every root in ~/.local/state/nix-apps (per user) and /var/lib/nix-apps
# (system services) pins one store path built from the flake. `list` shows
# them, `status` compares each with what the current flake would build,
# `update` re-points a root, `clean` drops it (the store path survives
# until the next GC). The launchers themselves only build when a root is
# missing; this is the tool for refreshing one before that happens.
flake="${NIX_APPS_FLAKE:-git+file:///etc/nixos}"
user_root="${XDG_STATE_HOME:-$HOME/.local/state}/nix-apps"
system_root="${NIX_APPS_SYSTEM_ROOT:-/var/lib/nix-apps}"

usage() {
  cat << 'EOF'
usage: nix-apps COMMAND [NAME...]

commands:
  list              every on-demand root with its pinned store path
  status            compare each root with the current flake
  update [NAME...]  rebuild roots from the current flake (default: all managed)
  clean NAME...     remove roots; the store path stays until the next GC

A root is a GC root: it pins the store path of one flake attr until
`nix-apps update` re-points it or `nix-apps clean` removes it. The first
call of a launcher after a clean builds the app again; `update` re-points
without waiting for that call.
EOF
}

die() {
  printf 'nix-apps: %s\n' "$*" >&2
  exit 1
}

# Root name -> flake attr, where the two differ.
map_attr() {
  case "$1" in
    docling) printf '%s\n' docling-env ;;
    *) printf '%s\n' "$1" ;;
  esac
}

resolve_attr() {
  local name="$1" attr
  for attr in "$(map_attr "$name")" "$name" "$name-env"; do
    if nix eval --raw "$flake#$attr.name" > /dev/null 2>&1; then
      printf '%s\n' "$attr"
      return 0
    fi
  done
  return 1
}

# Iterate all roots as: scope<TAB>name<TAB>path.
each_root() {
  local dir scope path
  for scope in user system; do
    case "$scope" in
      user) dir="$user_root" ;;
      system) dir="$system_root" ;;
    esac
    [ -d "$dir" ] || continue
    for path in "$dir"/*; do
      [ -L "$path" ] || continue
      printf '%s\t%s\t%s\n' "$scope" "${path##*/}" "$path"
    done
  done
}

cmd_list() {
  printf '%-26s %-7s %-36s %s\n' NAME SCOPE PINNED TARGET
  each_root | while IFS=$'\t' read -r scope name path; do
    target=$(readlink -f "$path" 2> /dev/null || true)
    [ -n "$target" ] || continue
    printf '%-26s %-7s %-36s %s\n' "$name" "$scope" "${target##*/}" "$target"
  done
}

cmd_status() {
  local scope name path target attr want state
  printf '%-26s %-7s %-9s %-34s %s\n' NAME SCOPE STATE PINNED CURRENT
  each_root | while IFS=$'\t' read -r scope name path; do
    target=$(readlink -f "$path" 2> /dev/null || true)
    [ -n "$target" ] || continue
    if ! attr=$(resolve_attr "$name"); then
      printf '%-26s %-7s %-9s %-34s %s\n' "$name" "$scope" external "${target##*/}" -
      continue
    fi
    want=$(nix eval --raw "$flake#$attr.outPath" 2> /dev/null || true)
    if [ "$want" = "$target" ]; then state=current; else state=stale; fi
    printf '%-26s %-7s %-9s %-34s %s\n' "$name" "$scope" "$state" "${target##*/}" "${want##*/}"
  done
}

# Choose the output that carries bin/<name>, else the first one with bin/,
# else the first output — the same rule lib/on-demand-app.nix uses.
pick_output() {
  local name="$1" candidate picked
  picked=""
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    if [ -x "$candidate/bin/$name" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    if [ -z "$picked" ] && [ -d "$candidate/bin" ]; then
      picked="$candidate"
      continue
    fi
  done <<< "$2"
  if [ -n "$picked" ]; then
    printf '%s\n' "$picked"
    return 0
  fi
  printf '%s\n' "$2" | head -n 1
}

update_one() {
  local scope="$1" name="$2" path="$3" attr out picked old
  if ! attr=$(resolve_attr "$name"); then
    printf '%-26s %-7s skipped (no flake attr)\n' "$name" "$scope"
    return 0
  fi
  out=$(nix build --no-link --print-out-paths "$flake#$attr")
  picked=$(pick_output "$name" "$out")
  [ -n "$picked" ] || die "no output for $attr"
  old=$(readlink -f "$path" 2> /dev/null || printf '%s' "(none)")
  rm -f "$path"
  nix-store --add-root "$path" --indirect --realise "$picked" > /dev/null
  printf '%-26s %-7s %-36s -> %s\n' "$name" "$scope" "${old##*/}" "${picked##*/}"
  if [ "$scope" = system ]; then
    printf '  restart the service that reads it: sudo systemctl restart %s\n' "$name"
  fi
}

cmd_update() {
  local want scope name path found
  if [ "$#" -eq 0 ]; then
    each_root | while IFS=$'\t' read -r scope name path; do
      update_one "$scope" "$name" "$path"
    done
    return 0
  fi
  for want in "$@"; do
    found=0
    while IFS=$'\t' read -r scope name path; do
      [ "$name" = "$want" ] || continue
      found=1
      update_one "$scope" "$name" "$path"
    done < <(each_root)
    [ "$found" = 1 ] || printf 'nix-apps: no root named %s\n' "$want" >&2
  done
}

cmd_clean() {
  [ "$#" -gt 0 ] || die 'clean needs at least one name'
  local want scope name path found
  for want in "$@"; do
    found=0
    while IFS=$'\t' read -r scope name path; do
      [ "$name" = "$want" ] || continue
      found=1
      rm -f "$path"
      printf '%-26s %-7s removed (store path stays until GC)\n' "$name" "$scope"
    done < <(each_root)
    [ "$found" = 1 ] || printf 'nix-apps: no root named %s\n' "$want" >&2
  done
}

main() {
  [ "$#" -gt 0 ] || {
    usage
    exit 1
  }
  local cmd="$1"
  shift
  case "$cmd" in
    list) cmd_list ;;
    status) cmd_status ;;
    update) cmd_update "$@" ;;
    clean) cmd_clean "$@" ;;
    -h | --help | help) usage ;;
    *) die "unknown command: $cmd" ;;
  esac
}

main "$@"
