#!/usr/bin/env bash
# Parity harness: run the shipped shell scripts and the Rust ports side by side
# against the same fake external tools and compare every observable: exit code,
# stdout bytes, stderr bytes, the argv each tool received, the clipboard
# payloads, and a sha256 snapshot of the temporary HOME tree (so file mutations
# and downloads are compared too).
#
#   tests/parity.sh [--bin-dir DIR]
#
# Env: CARGO_TARGET_DIR selects the target directory (default: ../target),
#      LOCAL_BIN_SYSTEM_BIN overrides the directory holding the released
#      binaries.
#
# The fakes are shell scripts first on PATH; a second directory carries
# symlinks to the real utilities the shell originals drive (grep/sed/awk/jq/git
# and friends). HOME, TMPDIR and every state file live in a temporary tree;
# nothing here touches the real Steam userdata, clipboard, journal or AI asset
# tree.

set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/.." && pwd)
REPO=$(cd -- "$ROOT/../.." && pwd)
ORIGINALS=$REPO/packages/local-bin/bin
BIN_DIR=${LOCAL_BIN_SYSTEM_BIN:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}

while [ $# -gt 0 ]; do
  case "$1" in
    --bin-dir)
      BIN_DIR=$2
      shift 2
      ;;
    *)
      echo "parity: unknown argument '$1'" >&2
      exit 2
      ;;
  esac
done

WORK=$(mktemp -d "${TMPDIR:-/tmp}/local-bin-system-parity.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT

mkdir -p "$WORK/home" "$WORK/tmp" "$WORK/case" "$WORK/fakes" "$WORK/utils"
UTILS=$WORK/utils
for tool in awk basename cat cp cut dirname find grep git head jq ls mkdir mktemp \
  mv rm sed seq sha256sum sort tail tr wc xargs; do
  if resolved=$(command -v "$tool" 2> /dev/null); then
    ln -sf "$resolved" "$UTILS/$tool"
  fi
done

FAILED=0
CHECKS=0
pass() {
  CHECKS=$((CHECKS + 1))
  printf 'PASS  %s\n' "$1"
}
fail() {
  CHECKS=$((CHECKS + 1))
  FAILED=1
  printf 'FAIL  %s\n' "$1" >&2
}
section() { printf '\n== %s ==\n' "$1"; }

make_fake() {
  local directory=$1 name=$2 body=$3
  printf '#!/bin/sh\n%s\n' "$body" > "$directory/$name"
  chmod +x "$directory/$name"
}

reset() {
  rm -rf "${WORK:?}/home" "${WORK:?}/tmp" "${WORK:?}/case"
  mkdir -p "$WORK/home" "$WORK/tmp" "$WORK/case"
}

SETUP=""
setup() { SETUP=$1; }

normalize() {
  sed -E \
    -e "s|$WORK|WORK|g" \
    -e "s|maimscript-[A-Za-z0-9]{6}|maimscript-TMP|g" \
    -e "s|tmp\.[A-Za-z0-9]{10}|tmp.TMP|g" \
    -e "s/page=[0-9]+/page=N/g"
}

snapshot() {
  if [ -d "$WORK/home" ]; then
    (cd "$WORK/home" && find . -type f -not -path "*/.git/*" | sort | while IFS= read -r file; do
      printf '%s ' "$file"
      sha256sum "$file" | cut -d' ' -f1
    done)
  fi
}

invoke() {
  local interpreter=$1 program=$2 fake_path=$3 input=$4
  shift 4
  local -a overrides=()
  while [ "${1:-}" != "--" ]; do
    overrides+=("$1")
    shift
  done
  shift
  local -a envs=(
    PATH="$fake_path:$UTILS"
    HOME="$WORK/home"
    TMPDIR="$WORK/tmp"
    XDG_CONFIG_HOME="$WORK/home/.config"
    XDG_CACHE_HOME="$WORK/home/.cache"
    XDG_MUSIC_DIR="$WORK/home/Music"
    XDG_PICTURES_DIR="$WORK/home/pictures"
    LANG=C
    LC_ALL=C
  )
  envs+=("${overrides[@]}")
  envs+=(
    FAKE_ARGV_LOG="$WORK/$SIDE.argv"
    FAKE_CLIP="$WORK/$SIDE.clip"
    FAKE_DMENU_IN="$WORK/$SIDE.dmenu"
    FAKE_RUNNING="$WORK/$SIDE.running"
    FAKE_STATE="$WORK/$SIDE.state"
  )
  local stdin_source=$input
  [ "$stdin_source" = "-" ] && stdin_source=/dev/null
  if [ "$interpreter" = direct ]; then
    (cd "$WORK/case" && env -i "${envs[@]}" "$program" "$@") < "$stdin_source"
  else
    # `env -i` reseats PATH, so the interpreter itself must be an absolute path
    # (resolved with the harness' own PATH).
    local interpreter_path
    interpreter_path=$(command -v "$interpreter")
    (cd "$WORK/case" && env -i "${envs[@]}" "$interpreter_path" "$program" "$@") < "$stdin_source"
  fi
}

# compare label interpreter original rust fake_path stdin [ENV=VALUE ...] -- args
compare() {
  local label=$1 interpreter=$2 original=$3 rust=$4 fake_path=$5 input=$6
  shift 6
  local -a overrides=()
  while [ $# -gt 0 ] && [ "${1:-}" != "--" ]; do
    overrides+=("$1")
    shift
  done
  if [ $# -gt 0 ]; then shift; fi

  local status
  rm -f "$WORK"/*.argv "$WORK"/*.clip "$WORK"/*.dmenu "$WORK"/*.running "$WORK"/*.state
  reset
  if [ -n "$SETUP" ]; then $SETUP; fi
  SIDE=o
  set +e
  invoke "$interpreter" "$original" "$fake_path" "$input" "${overrides[@]}" -- "$@" \
    > "$WORK/o.out" 2> "$WORK/o.err"
  status=$?
  set -e
  printf '%s' "$status" > "$WORK/o.status"
  snapshot > "$WORK/o.tree"

  reset
  if [ -n "$SETUP" ]; then $SETUP; fi
  SIDE=r
  set +e
  invoke direct "$rust" "$fake_path" "$input" "${overrides[@]}" -- "$@" \
    > "$WORK/r.out" 2> "$WORK/r.err"
  status=$?
  set -e
  printf '%s' "$status" > "$WORK/r.status"
  snapshot > "$WORK/r.tree"

  local ok=1 detail=""
  local stream kind
  for kind in status tree; do
    if ! diff -q "$WORK/o.$kind" "$WORK/r.$kind" > /dev/null; then
      ok=0
      detail+="  $kind diff:"$'\n'"$(diff -u "$WORK/o.$kind" "$WORK/r.$kind" | normalize | head -20 || true)"$'\n'
    fi
  done
  for stream in out err; do
    if ! diff -q <(normalize < "$WORK/o.$stream") <(normalize < "$WORK/r.$stream") > /dev/null; then
      ok=0
      detail+="  $stream diff:"$'\n'"$(diff -u <(normalize < "$WORK/o.$stream") <(normalize < "$WORK/r.$stream") | head -30 || true)"$'\n'
    fi
  done
  for stream in argv clip; do
    if ! diff -q <(artifact "$stream" o | normalize | sort) \
      <(artifact "$stream" r | normalize | sort) > /dev/null; then
      ok=0
      detail+="  $stream diff:"$'\n'"$(diff -u <(artifact "$stream" o | normalize | sort) <(artifact "$stream" r | normalize | sort) | head -30 || true)"$'\n'
    fi
  done

  if [ "$ok" = 1 ]; then
    pass "$label"
  else
    fail "$label"
    printf '%s' "$detail" >&2
  fi
}

artifact() {
  local kind=$1 side_name=$2 file
  file="$WORK/$side_name.$kind"
  [ -f "$file" ] && cat -- "$file"
  return 0
}

# ---------------------------------------------------------------------------
section "steam-cloud-fix"
STEAM_FAKES=$WORK/fakes/steam
mkdir -p "$STEAM_FAKES"
make_fake "$STEAM_FAKES" pgrep 'exit "${FAKE_PGREP:-1}"'
make_fake "$STEAM_FAKES" date 'printf "%s\n" "${FAKE_DATE:-20240102-030405}"'
make_fake "$STEAM_FAKES" sleep 'printf "sleep %s\n" "$*" >> "$FAKE_ARGV_LOG"; exit "${FAKE_SLEEP_CODE:-0}"'
make_fake "$STEAM_FAKES" env 'printf "env %s\n" "$*" >> "$FAKE_ARGV_LOG"'
make_fake "$STEAM_FAKES" pkill 'printf "pkill %s\n" "$*" >> "$FAKE_ARGV_LOG"'
make_fake "$STEAM_FAKES" timeout 'printf "timeout %s\n" "$*" >> "$FAKE_ARGV_LOG"'
make_fake "$STEAM_FAKES" steam 'exit 0'

setup_steam() {
  local root=$WORK/home/steam
  mkdir -p "$root/userdata/123/config" "$root/userdata/123/294100/ac/deep" "$root/logs"
  printf '%s\n' '"UserLocalConfigStore"' '{' '	"apps"' '	{' '		"294100"' '		{' '			"last_sync_state"		"changesincloud"' '		}' '	}' '}' > "$root/userdata/123/config/localconfig.vdf"
  printf 'cache\n' > "$root/userdata/123/294100/remotecache.vdf"
  printf 'staging\n' > "$root/userdata/123/294100/ac/file"
  printf 'nested\n' > "$root/userdata/123/294100/ac/deep/file"
  printf '[2024-01-01 10:00:00] [AppID 294100] hello world\n[2024-01-01 10:00:01] [AppID 294100] sync step\n' > "$root/logs/cloud_log.txt"
}
setup setup_steam
compare "steam-cloud-fix: help" sh "$ORIGINALS/steam-cloud-fix" "$BIN_DIR/steam-cloud-fix" "$STEAM_FAKES" - -- --help
compare "steam-cloud-fix: status" sh "$ORIGINALS/steam-cloud-fix" "$BIN_DIR/steam-cloud-fix" "$STEAM_FAKES" - \
  STEAM_ROOT="$WORK/home/steam" BACKUP_ROOT="$WORK/home/backup" -- --status
compare "steam-cloud-fix: repair without start" sh "$ORIGINALS/steam-cloud-fix" "$BIN_DIR/steam-cloud-fix" "$STEAM_FAKES" - \
  STEAM_ROOT="$WORK/home/steam" BACKUP_ROOT="$WORK/home/backup" -- --no-start
compare "steam-cloud-fix: unknown argument" sh "$ORIGINALS/steam-cloud-fix" "$BIN_DIR/steam-cloud-fix" "$STEAM_FAKES" - -- --nope
setup_noop() { :; }
setup setup_noop
compare "steam-cloud-fix: missing steam root" sh "$ORIGINALS/steam-cloud-fix" "$BIN_DIR/steam-cloud-fix" "$STEAM_FAKES" - \
  STEAM_ROOT="$WORK/home/nope" -- --status
setup setup_steam
compare "steam-cloud-fix: start and wait" sh "$ORIGINALS/steam-cloud-fix" "$BIN_DIR/steam-cloud-fix" "$STEAM_FAKES" - \
  STEAM_ROOT="$WORK/home/steam" BACKUP_ROOT="$WORK/home/backup" -- --wait 0

# ---------------------------------------------------------------------------
section "dsh-statusline"
setup_repo() {
  local repo=$WORK/home/repo
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email parity@example.invalid
  git -C "$repo" config user.name parity
  printf 'one\n' > "$repo/tracked.txt"
  printf 'two\n' > "$repo/staged.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init
  printf 'one changed\n' > "$repo/tracked.txt"
  printf 'two changed\n' > "$repo/staged.txt"
  git -C "$repo" add staged.txt
  printf 'fresh\n' > "$repo/untracked.txt"
}
setup setup_repo
STATUSLINE_PAYLOAD=$WORK/statusline.json
printf '{"session_id":"s1","turn":7,"workspace":{"current_dir":"%s"},"context":{"ratio":0.42},"cost":{"total_yuan":0.1234}}' \
  "$WORK/home/repo" > "$STATUSLINE_PAYLOAD"
STATUSLINE_TOKEN_PAYLOAD=$WORK/statusline-tokens.json
printf '{"session_id":"s1","turn":7,"workspace":{"current_dir":"%s"},"context":{"estimated_tokens":54000,"max_tokens":128000}}' \
  "$WORK/home/repo" > "$STATUSLINE_TOKEN_PAYLOAD"
compare "dsh-statusline: help" sh "$ORIGINALS/dsh-statusline" "$BIN_DIR/dsh-statusline" "$UTILS" - -- --help
compare "dsh-statusline: unknown option" sh "$ORIGINALS/dsh-statusline" "$BIN_DIR/dsh-statusline" "$UTILS" - -- --nope
compare "dsh-statusline: protocol payload" sh "$ORIGINALS/dsh-statusline" "$BIN_DIR/dsh-statusline" "$UTILS" "$STATUSLINE_PAYLOAD"
compare "dsh-statusline: tokens/max" sh "$ORIGINALS/dsh-statusline" "$BIN_DIR/dsh-statusline" "$UTILS" "$STATUSLINE_TOKEN_PAYLOAD"
compare "dsh-statusline: parts filter" sh "$ORIGINALS/dsh-statusline" "$BIN_DIR/dsh-statusline" "$UTILS" "$STATUSLINE_PAYLOAD" \
  DSH_STATUSLINE_PARTS=turn
printf '{}' > "$WORK/empty.json"
compare "dsh-statusline: empty payload" sh "$ORIGINALS/dsh-statusline" "$BIN_DIR/dsh-statusline" "$UTILS" "$WORK/empty.json"
compare "dsh-statusline: git mode" sh "$ORIGINALS/dsh-statusline" "$BIN_DIR/dsh-statusline" "$UTILS" - -- --git "$WORK/home/repo"
compare "dsh-statusline: demo" sh "$ORIGINALS/dsh-statusline" "$BIN_DIR/dsh-statusline" "$UTILS" - -- --demo

# ---------------------------------------------------------------------------
section "sw"
SW_FAKES=$WORK/fakes/sw
mkdir -p "$SW_FAKES"
make_fake "$SW_FAKES" curl 'printf "curl %s\n" "$*" >> "$FAKE_ARGV_LOG"
destination=""; previous=""
for argument in "$@"; do
  if [ "$previous" = "-o" ]; then destination=$argument; fi
  previous=$argument
done
if [ -n "$destination" ]; then
  if [ "${FAKE_CURL_FAIL_DOWNLOAD:-0}" = 1 ]; then exit 7; fi
  printf "image-bytes" > "$destination"
else
  if [ "${FAKE_CURL_FAIL_API:-0}" = 1 ]; then exit 3; fi
  printf "%s" "${FAKE_JSON:-}"
fi'
setup_noop
setup setup_noop
SW_WALL=$(printf '{"data":[{"path":"https://w.wallhaven.cc/full/aa/wallpaper-aa.jpg"}]}')
SW_UNSPLASH=$(printf '[{"id":"abc","urls":{"raw":"https://images.unsplash.com/photo-1"}}]')
compare "sw: help" bash "$ORIGINALS/sw" "$BIN_DIR/sw" "$SW_FAKES" - -- --help
compare "sw: unknown option" bash "$ORIGINALS/sw" "$BIN_DIR/sw" "$SW_FAKES" - -- --nope
compare "sw: unknown source" bash "$ORIGINALS/sw" "$BIN_DIR/sw" "$SW_FAKES" - -- -S other
compare "sw: wallhaven download" bash "$ORIGINALS/sw" "$BIN_DIR/sw" "$SW_FAKES" - \
  FAKE_JSON="$SW_WALL" -- -q "a b" -C "#112233#445566"
compare "sw: wallhaven no results" bash "$ORIGINALS/sw" "$BIN_DIR/sw" "$SW_FAKES" - \
  FAKE_JSON='{"data":[]}' --
compare "sw: wallhaven api failure" bash "$ORIGINALS/sw" "$BIN_DIR/sw" "$SW_FAKES" - \
  FAKE_CURL_FAIL_API=1 --
compare "sw: unsplash download" bash "$ORIGINALS/sw" "$BIN_DIR/sw" "$SW_FAKES" - \
  FAKE_JSON="$SW_UNSPLASH" -- -S unsplash -k KEY -q "x y"
compare "sw: unsplash missing key" bash "$ORIGINALS/sw" "$BIN_DIR/sw" "$SW_FAKES" - -- -S unsplash

# ---------------------------------------------------------------------------
section "shade"
SHADE_FAKES=$WORK/fakes/shade
mkdir -p "$SHADE_FAKES"
make_fake "$SHADE_FAKES" hyprctl 'if [ "$1" = "plugin" ]; then printf "%s\n" "${FAKE_PLUGIN-HyprWindowShade}"; exit 0; fi
printf "%s\n" "$*" >> "$FAKE_ARGV_LOG"
printf "dispatcher noise\n" >&2
exit 1'
make_fake "$SHADE_FAKES" fzf 'while IFS= read -r line; do printf "%s\n" "$line" >> "$FAKE_DMENU_IN"; done
printf "%s" "${FAKE_SEL:-}"'
setup_shaders() {
  local directory=$WORK/home/.config/hypr/shaders
  mkdir -p "$directory"
  printf '// HyprWindowShade: CRT scanlines\nvoid main() {}\n' > "$directory/crt.glsl"
  printf '// HyprWindowShade: dim it\nvoid main() {}\n' > "$directory/dim.glsl"
}
setup setup_shaders
compare "shade: help" sh "$ORIGINALS/shade" "$BIN_DIR/shade" "$SHADE_FAKES" - -- --help
compare "shade: list" sh "$ORIGINALS/shade" "$BIN_DIR/shade" "$SHADE_FAKES" - -- list
compare "shade: on" sh "$ORIGINALS/shade" "$BIN_DIR/shade" "$SHADE_FAKES" - -- on crt
compare "shade: off" sh "$ORIGINALS/shade" "$BIN_DIR/shade" "$SHADE_FAKES" - -- off
compare "shade: class with name" sh "$ORIGINALS/shade" "$BIN_DIR/shade" "$SHADE_FAKES" - -- class foot crt
compare "shade: class clear" sh "$ORIGINALS/shade" "$BIN_DIR/shade" "$SHADE_FAKES" - -- class foot
compare "shade: layer with name" sh "$ORIGINALS/shade" "$BIN_DIR/shade" "$SHADE_FAKES" - -- layer rofi crt
compare "shade: layer clear" sh "$ORIGINALS/shade" "$BIN_DIR/shade" "$SHADE_FAKES" - -- layer rofi
compare "shade: reload" sh "$ORIGINALS/shade" "$BIN_DIR/shade" "$SHADE_FAKES" - -- reload
compare "shade: unknown command" sh "$ORIGINALS/shade" "$BIN_DIR/shade" "$SHADE_FAKES" - -- bogus
compare "shade: missing shader" sh "$ORIGINALS/shade" "$BIN_DIR/shade" "$SHADE_FAKES" - -- on nope
compare "shade: plugin missing" sh "$ORIGINALS/shade" "$BIN_DIR/shade" "$SHADE_FAKES" - \
  FAKE_PLUGIN=Nothing -- reload
compare "shade: fzf picker" sh "$ORIGINALS/shade" "$BIN_DIR/shade" "$SHADE_FAKES" - \
  FAKE_SEL='crt             CRT scanlines' -- on

# ---------------------------------------------------------------------------
section "main-menu"
MENU_FAKES=$WORK/fakes/menu
mkdir -p "$MENU_FAKES"
make_fake "$MENU_FAKES" mpc 'printf "%s" "${FAKE_SONG:-}"'
make_fake "$MENU_FAKES" wl-copy 'while IFS= read -r -N 1 character; do printf "%s" "$character" >> "$FAKE_CLIP"; done'
make_fake "$MENU_FAKES" wl-paste 'printf "%s" "${FAKE_PASTE:-}"'
make_fake "$MENU_FAKES" trans 'printf "trans %s\n" "$*" >> "$FAKE_ARGV_LOG"; printf "%s" "${FAKE_TRANS:-}"'
make_fake "$MENU_FAKES" nc 'while IFS= read -r -N 1 character; do :; done; printf "%s\n" "${FAKE_NC:-termbin.invalid/xyz}"'
make_fake "$MENU_FAKES" notify-send 'printf "notify-send %s\n" "$*" >> "$FAKE_ARGV_LOG"'
make_fake "$MENU_FAKES" play-sound 'printf "play-sound %s\n" "$*" >> "$FAKE_ARGV_LOG"'
make_fake "$MENU_FAKES" vicinae 'while IFS= read -r line; do printf "in %s\n" "$line" >> "$FAKE_ARGV_LOG"; done
printf "%s" "${FAKE_SEL:-}"'
make_fake "$MENU_FAKES" sleep 'printf "%s %s\n" "${0##*/}" "$*" >> "$FAKE_ARGV_LOG"'
setup_noop
setup setup_noop
MENU_SONG=$'Artist\nTitle\nAlbum\nName\na/b.mp3'
compare "main-menu: list" sh "$ORIGINALS/main-menu" "$BIN_DIR/main-menu" "$MENU_FAKES" - -- --list
compare "main-menu: help" sh "$ORIGINALS/main-menu" "$BIN_DIR/main-menu" "$MENU_FAKES" - -- --help
compare "main-menu: run without action" sh "$ORIGINALS/main-menu" "$BIN_DIR/main-menu" "$MENU_FAKES" - -- --run
compare "main-menu: unknown action" sh "$ORIGINALS/main-menu" "$BIN_DIR/main-menu" "$MENU_FAKES" - -- --run nope
compare "main-menu: title copy" sh "$ORIGINALS/main-menu" "$BIN_DIR/main-menu" "$MENU_FAKES" - \
  FAKE_SONG="$MENU_SONG" -- --run title_copy
compare "main-menu: artist copy" sh "$ORIGINALS/main-menu" "$BIN_DIR/main-menu" "$MENU_FAKES" - \
  FAKE_SONG="$MENU_SONG" -- --run artist_copy
compare "main-menu: album copy" sh "$ORIGINALS/main-menu" "$BIN_DIR/main-menu" "$MENU_FAKES" - \
  FAKE_SONG="$MENU_SONG" -- --run album_copy
compare "main-menu: path copy" sh "$ORIGINALS/main-menu" "$BIN_DIR/main-menu" "$MENU_FAKES" - \
  FAKE_SONG="$MENU_SONG" -- --run path_copy
compare "main-menu: pipewire output" sh "$ORIGINALS/main-menu" "$BIN_DIR/main-menu" "$MENU_FAKES" - -- --run pipewire_output
compare "main-menu: alsa output" sh "$ORIGINALS/main-menu" "$BIN_DIR/main-menu" "$MENU_FAKES" - -- --run alsa_output
compare "main-menu: translate" sh "$ORIGINALS/main-menu" "$BIN_DIR/main-menu" "$MENU_FAKES" - \
  FAKE_PASTE=hello FAKE_TRANS=privet -- --run translate
compare "main-menu: termbin" sh "$ORIGINALS/main-menu" "$BIN_DIR/main-menu" "$MENU_FAKES" - \
  FAKE_PASTE=payload FAKE_NC=termbin.invalid/abc -- --run termbin
compare "main-menu: dmenu selection" sh "$ORIGINALS/main-menu" "$BIN_DIR/main-menu" "$MENU_FAKES" - \
  FAKE_SEL='translate
album_copy
' FAKE_PASTE=hello FAKE_TRANS=privet FAKE_SONG="$MENU_SONG" --
compare "main-menu: dmenu unterminated line" sh "$ORIGINALS/main-menu" "$BIN_DIR/main-menu" "$MENU_FAKES" - \
  FAKE_SEL=title_copy FAKE_SONG="$MENU_SONG" --

# ---------------------------------------------------------------------------
section "surfingkeys-extension-patch"
SK_FAKES=$WORK/fakes/surfingkeys
mkdir -p "$SK_FAKES"
make_fake "$SK_FAKES" logger 'printf "%s\n" "$*" >> "$FAKE_ARGV_LOG"; exit "${FAKE_LOGGER_CODE:-0}"'
SK_EXTENSION=$WORK/home/.config/vivaldi/Default/Extensions/gfbliohnnapiefjpjlpjnehglfpaknnc
setup_surfingkeys() {
  mkdir -p "$SK_EXTENSION/1.18.0" "$SK_EXTENSION/1.19.3/pages"
  printf '(()=>{"use strict";var a=e.localPath?B(e.localPath,function(t){e.snippets=t,o(e)},x);}))();\n' > "$SK_EXTENSION/1.19.3/background.js"
  printf 'table { background-color: #f8f8f8; }\n' > "$SK_EXTENSION/1.19.3/pages/markdown.css"
  printf 'old\n' > "$SK_EXTENSION/1.18.0/background.js"
}
setup setup_surfingkeys
compare "surfingkeys: full patch" bash "$ORIGINALS/surfingkeys-extension-patch" "$BIN_DIR/surfingkeys-extension-patch" "$SK_FAKES" - --
setup_surfingkeys_missing() {
  mkdir -p "$SK_EXTENSION/1.19.3"
  printf 'unrelated-content\n' > "$SK_EXTENSION/1.19.3/background.js"
}
setup setup_surfingkeys_missing
compare "surfingkeys: missing anchors" bash "$ORIGINALS/surfingkeys-extension-patch" "$BIN_DIR/surfingkeys-extension-patch" "$SK_FAKES" - --
setup_surfingkeys_none() { mkdir -p "$SK_EXTENSION"; }
setup setup_surfingkeys_none
compare "surfingkeys: no version directories" bash "$ORIGINALS/surfingkeys-extension-patch" "$BIN_DIR/surfingkeys-extension-patch" "$SK_FAKES" - --

# ---------------------------------------------------------------------------
section "dsh-url"
URL_FAKES=$WORK/fakes/dsh-url
mkdir -p "$URL_FAKES"
make_fake "$URL_FAKES" journalctl 'printf "%s" "${FAKE_JOURNAL:-}"'
make_fake "$URL_FAKES" wl-copy 'while IFS= read -r -N 1 character; do printf "%s" "$character" >> "$FAKE_CLIP"; done'
make_fake "$URL_FAKES" xclip 'while IFS= read -r -N 1 character; do printf "%s" "$character" >> "$FAKE_CLIP"; done'
make_fake "$URL_FAKES" xdg-open 'printf "xdg-open %s\n" "$*" >> "$FAKE_ARGV_LOG"; exit "${FAKE_OPEN_CODE:-0}"'
setup_noop
setup setup_noop
URL_JOURNAL='2024-01-01 10:00:00 dsh web: opening the default browser
2024-01-01 10:00:01 dsh web: http://127.0.0.1:3000/?token=abc (LAN: http://192.168.1.5:3000/?token=abc)
'
compare "dsh-url: help" sh "$ORIGINALS/dsh-url" "$BIN_DIR/dsh-url" "$URL_FAKES" - -- --help
compare "dsh-url: loopback" sh "$ORIGINALS/dsh-url" "$BIN_DIR/dsh-url" "$URL_FAKES" - \
  FAKE_JOURNAL="$URL_JOURNAL" --
compare "dsh-url: lan" sh "$ORIGINALS/dsh-url" "$BIN_DIR/dsh-url" "$URL_FAKES" - \
  FAKE_JOURNAL="$URL_JOURNAL" -- --lan
compare "dsh-url: lan missing" sh "$ORIGINALS/dsh-url" "$BIN_DIR/dsh-url" "$URL_FAKES" - \
  FAKE_JOURNAL='dsh web: http://127.0.0.1:3000/' -- --lan
compare "dsh-url: copy" sh "$ORIGINALS/dsh-url" "$BIN_DIR/dsh-url" "$URL_FAKES" - \
  FAKE_JOURNAL="$URL_JOURNAL" -- --copy
compare "dsh-url: open" sh "$ORIGINALS/dsh-url" "$BIN_DIR/dsh-url" "$URL_FAKES" - \
  FAKE_JOURNAL="$URL_JOURNAL" -- --open
compare "dsh-url: unknown option" sh "$ORIGINALS/dsh-url" "$BIN_DIR/dsh-url" "$URL_FAKES" - \
  FAKE_JOURNAL="$URL_JOURNAL" -- --bogus
compare "dsh-url: no journal line" sh "$ORIGINALS/dsh-url" "$BIN_DIR/dsh-url" "$URL_FAKES" - -- --

# ---------------------------------------------------------------------------
section "qr"
QR_FAKES=$WORK/fakes/qr
mkdir -p "$QR_FAKES"
make_fake "$QR_FAKES" grim 'if [ "${FAKE_GRIM_FAIL:-0}" = 1 ]; then exit 1; fi
case "$1" in
  -g) if [ "$3" = "-" ]; then printf "pngdata"; else printf "pngdata" > "$3"; fi ;;
  -) printf "pngdata" ;;
esac'
make_fake "$QR_FAKES" slurp 'printf "%s\n" "${FAKE_GEOM:-10,20 100x100}"'
make_fake "$QR_FAKES" wl-copy 'while IFS= read -r -N 1 character; do printf "%s" "$character" >> "$FAKE_CLIP"; done'
make_fake "$QR_FAKES" wl-paste 'printf "%s" "${FAKE_PASTE:-text}"'
make_fake "$QR_FAKES" notify-send 'printf "notify-send %s\n" "$*" >> "$FAKE_ARGV_LOG"'
make_fake "$QR_FAKES" qrencode 'printf "%s" "${FAKE_QRENCODE_OUT:-QR}"'
make_fake "$QR_FAKES" zbarimg 'printf "%s" "${FAKE_SCAN:-}"'
make_fake "$QR_FAKES" convert 'printf "convert %s\n" "$*" >> "$FAKE_ARGV_LOG"'
setup_noop
setup setup_noop
compare "qr: help" sh "$ORIGINALS/qr" "$BIN_DIR/qr" "$QR_FAKES" - -- --help
compare "qr: default screenshot" sh "$ORIGINALS/qr" "$BIN_DIR/qr" "$QR_FAKES" - --
compare "qr: select" sh "$ORIGINALS/qr" "$BIN_DIR/qr" "$QR_FAKES" - -- select
compare "qr: gen" sh "$ORIGINALS/qr" "$BIN_DIR/qr" "$QR_FAKES" - -- gen
compare "qr: scan" sh "$ORIGINALS/qr" "$BIN_DIR/qr" "$QR_FAKES" - \
  FAKE_SCAN='SCANRESULT' -- qr
compare "qr: scan without data" sh "$ORIGINALS/qr" "$BIN_DIR/qr" "$QR_FAKES" - -- qr
compare "qr: scan grim failure" sh "$ORIGINALS/qr" "$BIN_DIR/qr" "$QR_FAKES" - \
  FAKE_GRIM_FAIL=1 -- qr
compare "qr: unknown subcommand" sh "$ORIGINALS/qr" "$BIN_DIR/qr" "$QR_FAKES" - -- bogus

# ---------------------------------------------------------------------------
section "pdf2md"
PDF_FAKES=$WORK/fakes/pdf2md
mkdir -p "$PDF_FAKES"
make_fake "$PDF_FAKES" docling 'printf "docling %s\n" "$*" >> "$FAKE_ARGV_LOG"
printf "HF_HOME=%s\n" "${HF_HOME-unset}" >> "$FAKE_ARGV_LOG"
printf "docling-out\n"; printf "docling-err\n" >&2
exit "${FAKE_DOCLING_CODE:-0}"'
PDF_ORIGINAL=$WORK/pdf2md-shell
sed "s|@DOCLING_BIN@|$PDF_FAKES/docling|" "$ORIGINALS/pdf2md" > "$PDF_ORIGINAL"
setup_noop
setup setup_noop
compare "pdf2md: help" sh "$PDF_ORIGINAL" "$BIN_DIR/pdf2md" "$PDF_FAKES" - -- --help
compare "pdf2md: no arguments" sh "$PDF_ORIGINAL" "$BIN_DIR/pdf2md" "$PDF_FAKES" - --
compare "pdf2md: -o rewriting" sh "$PDF_ORIGINAL" "$BIN_DIR/pdf2md" "$PDF_FAKES" - -- -o out/ a.pdf b.pdf
compare "pdf2md: --output= rewriting" sh "$PDF_ORIGINAL" "$BIN_DIR/pdf2md" "$PDF_FAKES" - -- --output=out a.pdf
compare "pdf2md: pass-through" sh "$PDF_ORIGINAL" "$BIN_DIR/pdf2md" "$PDF_FAKES" - -- --to json f.pdf
compare "pdf2md: missing -o value" sh "$PDF_ORIGINAL" "$BIN_DIR/pdf2md" "$PDF_FAKES" - -- -o
compare "pdf2md: docling failure" sh "$PDF_ORIGINAL" "$BIN_DIR/pdf2md" "$PDF_FAKES" - \
  FAKE_DOCLING_CODE=7 -- a.pdf

# ---------------------------------------------------------------------------
section "upstream-radar"
UP_FAKES=$WORK/fakes/upstream-radar
mkdir -p "$UP_FAKES"
make_fake "$UP_FAKES" env 'printf "env %s\n" "$*" >> "$FAKE_ARGV_LOG"; printf "env-out\n"; exit "${FAKE_ENV_CODE:-0}"'
setup_noop
setup setup_noop
compare "upstream-radar: help" sh "$ORIGINALS/upstream-radar" "$BIN_DIR/upstream-radar" "$UP_FAKES" - -- --help
compare "upstream-radar: pinned npx argv" sh "$ORIGINALS/upstream-radar" "$BIN_DIR/upstream-radar" "$UP_FAKES" - \
  -- scan https://example.invalid/x --fail-on never
compare "upstream-radar: env status" sh "$ORIGINALS/upstream-radar" "$BIN_DIR/upstream-radar" "$UP_FAKES" - \
  FAKE_ENV_CODE=9 -- inspect pkg@1 --deep

# ---------------------------------------------------------------------------
section "vsmlrt-models"
VS_FAKES=$WORK/fakes/vsmlrt
mkdir -p "$VS_FAKES"
make_fake "$VS_FAKES" curl 'printf "curl %s\n" "$*" >> "$FAKE_ARGV_LOG"
destination=""; previous=""
for argument in "$@"; do
  if [ "$previous" = "-o" ]; then destination=$argument; fi
  previous=$argument
done
[ -n "$destination" ] && printf "archive" > "$destination"
exit "${FAKE_CURL_CODE:-0}"'
make_fake "$VS_FAKES" 7zz 'printf "7zz %s pwd=%s\n" "$*" "$PWD" >> "$FAKE_ARGV_LOG"
exit "${FAKE_7ZZ_CODE:-0}"'
setup_noop
setup setup_noop
compare "vsmlrt-models: default version" sh "$ORIGINALS/vsmlrt-models" "$BIN_DIR/vsmlrt-models" "$VS_FAKES" - \
  VSMLRT_MODELS="$WORK/home/models" --
compare "vsmlrt-models: explicit version" sh "$ORIGINALS/vsmlrt-models" "$BIN_DIR/vsmlrt-models" "$VS_FAKES" - \
  VSMLRT_MODELS="$WORK/home/models" -- v16.0
compare "vsmlrt-models: curl failure" sh "$ORIGINALS/vsmlrt-models" "$BIN_DIR/vsmlrt-models" "$VS_FAKES" - \
  VSMLRT_MODELS="$WORK/home/models" FAKE_CURL_CODE=6 --
compare "vsmlrt-models: 7zz failure" sh "$ORIGINALS/vsmlrt-models" "$BIN_DIR/vsmlrt-models" "$VS_FAKES" - \
  VSMLRT_MODELS="$WORK/home/models" FAKE_7ZZ_CODE=8 --

# ---------------------------------------------------------------------------
section "nix-updates"
NIX_FAKES=$WORK/fakes/nix-updates
mkdir -p "$NIX_FAKES"
make_fake "$NIX_FAKES" nix 'printf "nix %s\n" "$*" >> "$FAKE_ARGV_LOG"; printf "nix-out\n"; exit "${FAKE_NIX_CODE:-0}"'
make_fake "$NIX_FAKES" dix 'printf "dix %s\n" "$*" >> "$FAKE_ARGV_LOG"; exit "${FAKE_DIX_CODE:-0}"'
setup_noop
setup setup_noop
compare "nix-updates: help" sh "$ORIGINALS/nix-updates" "$BIN_DIR/nix-updates" "$NIX_FAKES" - -- --help
compare "nix-updates: both tools" sh "$ORIGINALS/nix-updates" "$BIN_DIR/nix-updates" "$NIX_FAKES" - --
compare "nix-updates: nix failure ignored" sh "$ORIGINALS/nix-updates" "$BIN_DIR/nix-updates" "$NIX_FAKES" - \
  FAKE_NIX_CODE=3 --
compare "nix-updates: dix failure ignored" sh "$ORIGINALS/nix-updates" "$BIN_DIR/nix-updates" "$NIX_FAKES" - \
  FAKE_DIX_CODE=4 --

# ---------------------------------------------------------------------------
printf '\n%d checks, %d failed\n' "$CHECKS" "$FAILED"
exit "$FAILED"
