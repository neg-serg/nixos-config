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
  seed [NAME...]    pre-warm every launcher on PATH (or the named ones)
  update [NAME...]  rebuild roots from the current flake (default: all managed)
  clean NAME...     remove roots; the store path stays until the next GC

A root is a GC root: it pins the store path of one flake attr until
`nix-apps update` re-points it or `nix-apps clean` removes it. The first
call of a launcher after a clean builds the app again; `update` re-points
without waiting for that call, and creates a missing per-user root when
the name resolves to a flake attr (pre-warm a launcher that was never run).

`seed` is the offline recipe: it walks PATH, finds every on-demand launcher
(their store target lives in <name>-launchers) and pins the ones that have
no root yet. Run it once while online after a switch, and every launcher
works without network afterwards — the roots survive GC.
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
    searx) printf '%s\n' searxng ;;
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

create_user_root() {
  local name="$1" attr="$2" path="$user_root/$1" out picked
  out=$(nix build --no-link --print-out-paths "$flake#$attr")
  picked=$(pick_output "$name" "$out")
  [ -n "$picked" ] || die "no output for $attr"
  mkdir -p "$user_root"
  rm -f "$path"
  nix-store --add-root "$path" --indirect --realise "$picked" > /dev/null
  printf '%-26s %-7s created %s\n' "$name" user "${picked##*/}"
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
    if [ "$found" = 0 ]; then
      if attr=$(resolve_attr "$want"); then
        create_user_root "$want" "$attr"
      else
        printf 'nix-apps: no root named %s\n' "$want" >&2
      fi
    fi
  done
}

# Every on-demand launcher installed on PATH, as: root-name<TAB>launcher-target.
# The launcher symlink points into <hash>-<name>-launchers/bin/<name>, which is
# how the root name is recovered; aliases collapse onto the same root.
each_launcher() {
  local dir f target base
  local -a dirs=()
  IFS=':' read -r -a dirs <<< "${PATH:-}"
  for dir in "${dirs[@]}"; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*; do
      [ -L "$f" ] || continue
      target=$(readlink "$f" 2> /dev/null || true)
      case "$target" in
        */[0-9a-z]*-launchers/bin/*) ;;
        *) continue ;;
      esac
      base=$(basename "$(dirname "$(dirname "$target")")")
      base=${base#*-}
      printf '%s\t%s\n' "${base%-launchers}" "$target"
    done
  done
}

# Offline recipe: pin every launcher that has no root yet. The flake attr is
# read back from the generated dispatch script, so aliases and renamed roots
# (adb -> android-tools, js-debug -> vscode-js-debug) need no mapping table.
cmd_seed() {
  local name path attr out picked failed=0 w hit
  local -A seen=()
  printf '%-26s %-9s %s\n' NAME SCOPE RESULT
  while IFS=$'\t' read -r name path; do
    [ -n "$name" ] || continue
    [ -n "${seen[$name]:-}" ] && continue
    seen[$name]=1

    if [ "$#" -gt 0 ]; then
      hit=0
      for w in "$@"; do
        [ "$w" = "$name" ] && hit=1
      done
      [ "$hit" = 1 ] || continue
    fi

    if [ -e "$user_root/$name" ]; then
      printf '%-26s %-9s already pinned\n' "$name" user
      continue
    fi

    attr=$(sed -n 's/.*git+file:\/\/\/etc\/nixos#\([A-Za-z0-9._-]*\).*/\1/p' "$(readlink -f "$path" 2> /dev/null)" | head -n 1)
    if [ -z "$attr" ]; then
      printf '%-26s %-9s skipped (no attr in launcher)\n' "$name" user
      continue
    fi
    if ! out=$(nix build --no-link --print-out-paths "$flake#$attr" 2> /dev/null); then
      printf '%-26s %-9s FAILED (network or eval)\n' "$name" user
      failed=$((failed + 1))
      continue
    fi
    picked=$(pick_output "$name" "$out")
    if [ -z "$picked" ]; then
      printf '%-26s %-9s FAILED (no output)\n' "$name" user
      failed=$((failed + 1))
      continue
    fi
    mkdir -p "$user_root"
    rm -f "$user_root/$name"
    nix-store --add-root "$user_root/$name" --indirect --realise "$picked" > /dev/null
    printf '%-26s %-9s %s\n' "$name" user "${picked##*/}"
  done < <(each_launcher)
  [ "$failed" -eq 0 ] || die "$failed launcher(s) could not be seeded"
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
    seed) cmd_seed "$@" ;;
    update) cmd_update "$@" ;;
    clean) cmd_clean "$@" ;;
    -h | --help | help) usage ;;
    *) die "unknown command: $cmd" ;;
  esac
}

main "$@"
