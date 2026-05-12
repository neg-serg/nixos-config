#!/usr/bin/env bash
# hypr-shortcuts: Vicinae-powered quick commands for Hyprland helpers
set -euo pipefail
IFS=$'\n\t'

log() {
  printf 'hypr-shortcuts: %s\n' "$*" >&2
}

vicinae_bin="${VICINAE_BIN:-$(command -v vicinae 2> /dev/null || true)}"
if [ -z "$vicinae_bin" ]; then
  log "vicinae binary not found in PATH"
  exit 1
fi

runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

detect_signature() {
  local sig="${HYPRLAND_INSTANCE_SIGNATURE:-}"
  if [ -n "$sig" ] && [ -S "$runtime/hypr/$sig/.socket.sock" ]; then
    printf '%s\n' "$sig"
    return 0
  fi
  if [ -d "$runtime/hypr" ]; then
    local newest cand
    newest="$(ls -td "$runtime/hypr"/* 2> /dev/null | head -n1 || true)"
    if [ -n "$newest" ]; then
      cand="$(basename -- "$newest" || true)"
      if [ -S "$runtime/hypr/$cand/.socket.sock" ] || [ -S "$runtime/hypr/$cand/.socket2.sock" ]; then
        printf '%s\n' "$cand"
        return 0
      fi
    fi
  fi
  return 1
}

require_signature() {
  local sig
  if ! sig="$(detect_signature)"; then
    log "unable to locate Hyprland runtime socket under $runtime"
    return 1
  fi
  printf '%s\n' "$sig"
}

vicinae_menu() {
  "$vicinae_bin" dmenu --placeholder "shortcuts ❯❯" --section-title "Shortcuts {count}" --navigation-title "Shortcuts"
}

pick_secret() {
  local listing
  if ! listing="$(gopass ls --flat 2> /dev/null)"; then
    log "gopass ls failed"
    return 1
  fi
  listing="$(printf '%s\n' "$listing" | sed '/^\s*$/d')"
  [ -n "$listing" ] || return 1
  printf '%s\n' "$listing" | "$vicinae_bin" dmenu --placeholder "gopass ❯❯" --navigation-title "gopass" --section-title "Entries {count}"
}

fetch_window() {
  if ! command -v pypr-client > /dev/null 2>&1; then
    log "pypr-client helper not found"
    return 1
  fi
  pypr-client fetch_client_menu
}

open_socket_reader() {
  local sig
  sig="$(require_signature)" || return 1
  local sock="$runtime/hypr/$sig/.socket2.sock"
  kitty socat - "UNIX-CONNECT:${sock}"
}

tail_hyprland_logs() {
  local sig
  sig="$(require_signature)" || return 1
  local log_path="$runtime/hypr/$sig/hyprland.log"
  kitty tail -f "$log_path"
}

copy_password() {
  local entry
  entry="$(pick_secret)" || return 0
  gopass show -c "$entry"
}

update_password() {
  local entry
  entry="$(pick_secret)" || return 0
  kitty -- gopass generate -s --strict -t "$entry" && gopass show -c "$entry"
}

choices=(
  "Fetch window"
  "Hyprland socket"
  "Hyprland logs"
  "Copy password"
  "Update/Change password"
)

selection="$(printf '%s\n' "${choices[@]}" | vicinae_menu)" || exit 0
case "$selection" in
  "Fetch window")
    fetch_window
    ;;
  "Hyprland socket")
    open_socket_reader
    ;;
  "Hyprland logs")
    tail_hyprland_logs
    ;;
  "Copy password")
    copy_password
    ;;
  "Update/Change password")
    update_password
    ;;
  *) ;;
esac
