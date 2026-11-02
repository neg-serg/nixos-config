#!/usr/bin/env bash
# Parity harness: run the shipped scripts and the Rust ports side by side
# against the same fake external tools and compare every observable: exit code,
# stdout bytes, stderr bytes, the argv each tool received, and (for pass-2col)
# the dmenu input and clipboard payload.
#
#   tests/parity.sh [--bin-dir DIR]
#
# Env: CARGO_TARGET_DIR selects the target directory (default: ../target),
# LOCAL_BIN_SCRIPTS_BIN overrides the directory holding the released binaries.
#
# The fakes are /bin/sh scripts first on an otherwise empty PATH; HOME, TMPDIR
# and the fake programs' state files live in a temporary tree. Nothing here
# touches the real journal, the real password store, the real clipboard or
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/.." && pwd)
REPO=$(cd -- "$ROOT/../.." && pwd)
ORIGINALS=$REPO/packages/local-bin/scripts
BIN_DIR=${LOCAL_BIN_SCRIPTS_BIN:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}

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

BASH_BIN=$(command -v bash)
SH_BIN=$(command -v sh)
PYTHON_BIN=$(command -v python3)

WORK=$(mktemp -d "${TMPDIR:-/tmp}/local-bin-scripts-parity.XXXXXX")
cleanup() { rm -rf -- "$WORK"; }
trap cleanup EXIT

mkdir -p "$WORK/originals" "$WORK/home" "$WORK/tmp" "$WORK/case" "$WORK/fakes"

# The shell original of pass-2col drives find/grep/sed/sort/head/tr from PATH.
# Symlink only those real utilities into an isolated directory so the fake
# password-store helpers stay the only `pass`/`wl-copy`/`notify-send` on PATH.
UTILS=$WORK/fakes/utils
mkdir -p "$UTILS"
for tool in find grep sed sort head tr; do
  ln -s "$(command -v "$tool")" "$UTILS/$tool"
done
SYSTEM_UTILS_PATH=$UTILS

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

# Recover an original that the working tree no longer carries (the last
# committed revision before its deletion).
recover() {
  local name=$1
  if [ -r "$ORIGINALS/$name" ]; then
    cp -- "$ORIGINALS/$name" "$WORK/originals/$name"
    return 0
  fi
  local rel="packages/local-bin/scripts/$name"
  local deleted
  deleted=$(git -C "$REPO" log --all --format=%H -1 --diff-filter=D -- "$rel" 2> /dev/null || true)
  [ -n "$deleted" ] || return 1
  git -C "$REPO" show "$deleted^:$rel" > "$WORK/originals/$name" 2> /dev/null || return 1
  return 0
}

make_fake() {
  local directory=$1 name=$2 body=$3
  printf '%s' "$body" > "$directory/$name"
  chmod +x "$directory/$name"
}

# Run one side with a cleared environment. Side-specific state files are set
# after the overrides so a test cannot point both sides at the same log.
invoke() {
  local side=$1 interpreter=$2 program=$3 fake_path=$4
  shift 4
  local -a overrides=()
  while [ "${1:-}" != "--" ]; do
    overrides+=("$1")
    shift
  done
  shift
  local -a assignments=(
    PATH="$fake_path"
    HOME="$WORK/home"
    TMPDIR="$WORK/tmp"
    LANG=C
    LC_ALL=C
    COLUMNS=80
  )
  assignments+=("${overrides[@]}")
  assignments+=(
    FAKE_ARGV_LOG="$WORK/$side.argv"
    FAKE_DMENU_IN="$WORK/$side.dmenu"
    FAKE_CLIP="$WORK/$side.clip"
    FAKE_RUNNING_COUNTER="$WORK/$side.counter"
  )
  if [ "$interpreter" = direct ]; then
    env -i "${assignments[@]}" "$program" "$@"
  else
    env -i "${assignments[@]}" "$interpreter" "$program" "$@"
  fi
}

artifact() {
  if [ -f "$1" ]; then cat -- "$1"; fi
}

normalize() {
  local original=$1 rust=$2
  sed -E \
    -e "s|$original|PROG|g" \
    -e "s|$rust|PROG|g" \
    -e "s|$WORK/tmp/[A-Za-z0-9_]+|TMPDIR|g" \
    -e "s|$WORK|WORK|g"
}

# compare label interpreter original rust fake_path [ENV=VALUE ...] [-- args...]
compare() {
  local label=$1 interpreter=$2 original=$3 rust=$4 fake_path=$5
  shift 5
  local -a overrides=()
  while [ "${1:-}" != "--" ]; do
    overrides+=("$1")
    shift
  done
  shift
  local -a args=("$@")

  rm -f "$WORK"/o.out "$WORK"/o.err "$WORK"/r.out "$WORK"/r.err \
    "$WORK"/o.argv "$WORK"/o.dmenu "$WORK"/o.clip "$WORK"/o.counter \
    "$WORK"/r.argv "$WORK"/r.dmenu "$WORK"/r.clip "$WORK"/r.counter

  local original_status rust_status
  set +e
  (cd "$WORK/case" && invoke o "$interpreter" "$original" "$fake_path" "${overrides[@]}" -- "${args[@]}") \
    > "$WORK/o.out" 2> "$WORK/o.err"
  original_status=$?
  (cd "$WORK/case" && invoke r direct "$rust" "$fake_path" "${overrides[@]}" -- "${args[@]}") \
    > "$WORK/r.out" 2> "$WORK/r.err"
  rust_status=$?
  set -e

  local ok=1 detail=""
  if [ "$original_status" -ne "$rust_status" ]; then
    ok=0
    detail+="  exit: original=$original_status rust=$rust_status"$'\n'
  fi
  local stream
  for stream in out err argv dmenu clip; do
    local o_file r_file
    case "$stream" in
      out) o_file=$WORK/o.out r_file=$WORK/r.out ;;
      err) o_file=$WORK/o.err r_file=$WORK/r.err ;;
      argv) o_file=$WORK/o.argv r_file=$WORK/r.argv ;;
      dmenu) o_file=$WORK/o.dmenu r_file=$WORK/r.dmenu ;;
      clip) o_file=$WORK/o.clip r_file=$WORK/r.clip ;;
    esac
    if [ ! -f "$o_file" ] && [ ! -f "$r_file" ]; then
      continue
    fi
    local diff_output
    if ! diff_output=$(diff -u \
      <(artifact "$o_file" | normalize "$original" "$rust") \
      <(artifact "$r_file" | normalize "$original" "$rust")); then
      ok=0
      detail+="  $stream:"$'\n'"$diff_output"$'\n'
    fi
  done

  if [ "$ok" = 1 ]; then
    pass "$label"
  else
    fail "$label"
    printf '%s' "$detail" >&2
  fi
}

# A deviation that is only in diagnostic text: compare the exit status and the
# fact that both sides report something on stderr.
compare_status_only() {
  local label=$1 interpreter=$2 original=$3 rust=$4 fake_path=$5
  shift 5
  local -a overrides=()
  while [ "${1:-}" != "--" ]; do
    overrides+=("$1")
    shift
  done
  shift
  rm -f "$WORK"/o.out "$WORK"/o.err "$WORK"/r.out "$WORK"/r.err
  local original_status rust_status
  set +e
  (cd "$WORK/case" && invoke o "$interpreter" "$original" "$fake_path" "${overrides[@]}" -- "$@") \
    > "$WORK/o.out" 2> "$WORK/o.err"
  original_status=$?
  (cd "$WORK/case" && invoke r direct "$rust" "$fake_path" "${overrides[@]}" -- "$@") \
    > "$WORK/r.out" 2> "$WORK/r.err"
  rust_status=$?
  set -e
  if [ "$original_status" -eq "$rust_status" ] && [ -s "$WORK/o.err" ] && [ -s "$WORK/r.err" ]; then
    pass "$label (status and stderr presence; the text is a documented deviation)"
  else
    fail "$label: exit original=$original_status rust=$rust_status"
  fi
}

for tool in "$BASH_BIN" "$SH_BIN"; do
  [ -n "$tool" ] || {
    echo "parity: bash and sh are required" >&2
    exit 2
  }
done

for program in pass-2col punzip tty-log journal-clean music-highlevel; do
  [ -x "$BIN_DIR/$program" ] || {
    echo "parity: binary not executable: $BIN_DIR/$program" >&2
    echo "parity: run cargo build --locked first, or pass --bin-dir DIR" >&2
    exit 2
  }
done

# ---------------------------------------------------------------------------
section "originals"
for name in pass-2col punzip tty-log journal-clean.sh music-highlevel; do
  if recover "$name"; then
    printf 'found %s\n' "$name"
  else
    printf 'missing %s (parity for it will be skipped)\n' "$name"
  fi
done

# ---------------------------------------------------------------------------
section "punzip"
PUNZIP_FAKES=$WORK/fakes/punzip
mkdir -p "$PUNZIP_FAKES"
make_fake "$PUNZIP_FAKES" mkdir '#!/bin/sh
printf "mkdir\n" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf "  %s\n" "$arg" >> "$FAKE_ARGV_LOG"; done
exit "${FAKE_MKDIR_CODE:-0}"
'
make_fake "$PUNZIP_FAKES" unzip '#!/bin/sh
printf "unzip\n" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf "  %s\n" "$arg" >> "$FAKE_ARGV_LOG"; done
printf "unzip-stdout\n"
printf "unzip-stderr\n" >&2
exit "${FAKE_UNZIP_CODE:-0}"
'
PUNZIP_ORIG=$WORK/originals/punzip
PUNZIP_RUST=$BIN_DIR/punzip
if [ -r "$PUNZIP_ORIG" ]; then
  compare "punzip: no arguments" "$SH_BIN" "$PUNZIP_ORIG" "$PUNZIP_RUST" "$PUNZIP_FAKES" -- || true
  compare "punzip: -d without DIR" "$SH_BIN" "$PUNZIP_ORIG" "$PUNZIP_RUST" "$PUNZIP_FAKES" -- -d || true
  compare "punzip: -d with DIR and no archive" "$SH_BIN" "$PUNZIP_ORIG" "$PUNZIP_RUST" "$PUNZIP_FAKES" -- -d out || true
  compare "punzip: not a zip" "$SH_BIN" "$PUNZIP_ORIG" "$PUNZIP_RUST" "$PUNZIP_FAKES" -- a.tar.gz || true
  compare "punzip: in place" "$SH_BIN" "$PUNZIP_ORIG" "$PUNZIP_RUST" "$PUNZIP_FAKES" -- archive.zip || true
  compare "punzip: into a directory" "$SH_BIN" "$PUNZIP_ORIG" "$PUNZIP_RUST" "$PUNZIP_FAKES" -- -d "out dir" archive.ZIP || true
  compare "punzip: extra arguments" "$SH_BIN" "$PUNZIP_ORIG" "$PUNZIP_RUST" "$PUNZIP_FAKES" -- a.zip b.zip || true
  compare "punzip: unzip status" "$SH_BIN" "$PUNZIP_ORIG" "$PUNZIP_RUST" "$PUNZIP_FAKES" FAKE_UNZIP_CODE=7 -- a.zip || true
  compare "punzip: mkdir failure" "$SH_BIN" "$PUNZIP_ORIG" "$PUNZIP_RUST" "$PUNZIP_FAKES" FAKE_MKDIR_CODE=4 -- -d out a.zip || true
fi

# ---------------------------------------------------------------------------
section "tty-log"
TTY_FAKES=$WORK/fakes/tty-log
mkdir -p "$TTY_FAKES"
make_fake "$TTY_FAKES" mkdir '#!/bin/sh
printf "mkdir\n" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf "  %s\n" "$arg" >> "$FAKE_ARGV_LOG"; done
exit "${FAKE_MKDIR_CODE:-0}"
'
make_fake "$TTY_FAKES" tail '#!/bin/sh
printf "tail\n" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf "  %s\n" "$arg" >> "$FAKE_ARGV_LOG"; done
printf "%s" "${FAKE_TAIL_OUT:-}"
exit "${FAKE_TAIL_CODE:-0}"
'
make_fake "$TTY_FAKES" mv '#!/bin/sh
printf "mv\n" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf "  %s\n" "$arg" >> "$FAKE_ARGV_LOG"; done
exit "${FAKE_MV_CODE:-0}"
'
make_fake "$TTY_FAKES" script '#!/bin/sh
printf "script\n" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf "  %s\n" "$arg" >> "$FAKE_ARGV_LOG"; done
printf "script-stdout\n"
printf "script-stderr\n" >&2
exit "${FAKE_SCRIPT_CODE:-0}"
'
TTY_ORIG=$WORK/originals/tty-log
TTY_RUST=$BIN_DIR/tty-log
if [ -r "$TTY_ORIG" ]; then
  mkdir -p "$WORK/home/.cache/quickshell/tty-logs"
  compare "tty-log: no arguments" "$BASH_BIN" "$TTY_ORIG" "$TTY_RUST" "$TTY_FAKES" -- || true
  compare "tty-log: session capture" "$BASH_BIN" "$TTY_ORIG" "$TTY_RUST" "$TTY_FAKES" -- tty1 || true
  compare "tty-log: command capture" "$BASH_BIN" "$TTY_ORIG" "$TTY_RUST" "$TTY_FAKES" -- build nix build .#foo || true
  compare "tty-log: rotation payload" "$BASH_BIN" "$TTY_ORIG" "$TTY_RUST" "$TTY_FAKES" FAKE_TAIL_OUT=kept -- rotate || true
  compare "tty-log: tail failure" "$BASH_BIN" "$TTY_ORIG" "$TTY_RUST" "$TTY_FAKES" FAKE_TAIL_CODE=1 -- name || true
  compare "tty-log: script status" "$BASH_BIN" "$TTY_ORIG" "$TTY_RUST" "$TTY_FAKES" FAKE_SCRIPT_CODE=9 -- name || true
  TTY_NOTALL=$WORK/fakes/tty-log-notail
  mkdir -p "$TTY_NOTALL"
  cp -- "$TTY_FAKES/mkdir" "$TTY_FAKES/mv" "$TTY_FAKES/script" "$TTY_NOTALL/"
  compare "tty-log: missing tail" "$BASH_BIN" "$TTY_ORIG" "$TTY_RUST" "$TTY_NOTALL" -- name || true
  mkdir -p "$WORK/home/.cache/quickshell/tty-logs/blocked.log.tmp"
  compare "tty-log: unopenable rotation file" "$BASH_BIN" "$TTY_ORIG" "$TTY_RUST" "$TTY_FAKES" -- blocked || true
  rmdir "$WORK/home/.cache/quickshell/tty-logs/blocked.log.tmp"
  TTY_NOMV=$WORK/fakes/tty-log-nomv
  mkdir -p "$TTY_NOMV"
  cp -- "$TTY_FAKES/mkdir" "$TTY_FAKES/tail" "$TTY_FAKES/script" "$TTY_NOMV/"
  compare "tty-log: missing mv" "$BASH_BIN" "$TTY_ORIG" "$TTY_RUST" "$TTY_NOMV" -- name || true
  TTY_NOSCRIPT=$WORK/fakes/tty-log-noscript
  mkdir -p "$TTY_NOSCRIPT"
  cp -- "$TTY_FAKES/mkdir" "$TTY_FAKES/tail" "$TTY_FAKES/mv" "$TTY_NOSCRIPT/"
  compare "tty-log: missing script (session)" "$BASH_BIN" "$TTY_ORIG" "$TTY_RUST" "$TTY_NOSCRIPT" -- name || true
  compare "tty-log: missing script (command)" "$BASH_BIN" "$TTY_ORIG" "$TTY_RUST" "$TTY_NOSCRIPT" -- name echo hi || true
fi

# ---------------------------------------------------------------------------
section "journal-clean"
JOURNAL_FAKES=$WORK/fakes/journal
mkdir -p "$JOURNAL_FAKES"
make_fake "$JOURNAL_FAKES" journalctl '#!/bin/sh
printf "journalctl\n" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf "  %s\n" "$arg" >> "$FAKE_ARGV_LOG"; done
case " $* " in
  *" --disk-usage "*)
    printf "%s" "${FAKE_USAGE:-}"
    exit "${FAKE_USAGE_CODE:-0}"
    ;;
  *" --vacuum-time="*)
    exit "${FAKE_VACUUM_CODE:-0}"
    ;;
esac
exit 0
'
JOURNAL_NONE=$WORK/fakes/journal-none
mkdir -p "$JOURNAL_NONE"
JOURNAL_ORIG=$WORK/originals/journal-clean.sh
JOURNAL_RUST=$BIN_DIR/journal-clean
if [ -r "$JOURNAL_ORIG" ]; then
  compare "journal-clean: default vacuum" "$BASH_BIN" "$JOURNAL_ORIG" "$JOURNAL_RUST" "$JOURNAL_FAKES" FAKE_USAGE="user usage\n" -- || true
  compare "journal-clean: keep window" "$BASH_BIN" "$JOURNAL_ORIG" "$JOURNAL_RUST" "$JOURNAL_FAKES" FAKE_USAGE="" -- 7d || true
  compare "journal-clean: empty window" "$BASH_BIN" "$JOURNAL_ORIG" "$JOURNAL_RUST" "$JOURNAL_FAKES" -- "" || true
  compare "journal-clean: vacuum refused" "$BASH_BIN" "$JOURNAL_ORIG" "$JOURNAL_RUST" "$JOURNAL_FAKES" FAKE_VACUUM_CODE=1 -- || true
  compare "journal-clean: disk usage fails" "$BASH_BIN" "$JOURNAL_ORIG" "$JOURNAL_RUST" "$JOURNAL_FAKES" FAKE_USAGE_CODE=3 -- || true
  compare "journal-clean: no journalctl" "$BASH_BIN" "$JOURNAL_ORIG" "$JOURNAL_RUST" "$JOURNAL_NONE" -- || true
  mkdir -p "$WORK/runtime/hypr/sig"
  printf 'compositor output\n' > "$WORK/runtime/hypr/sig/hyprland.log"
  compare "journal-clean: truncates hyprland log" "$BASH_BIN" "$JOURNAL_ORIG" "$JOURNAL_RUST" "$JOURNAL_FAKES" \
    XDG_RUNTIME_DIR="$WORK/runtime" HYPRLAND_INSTANCE_SIGNATURE=sig -- || true
  compare "journal-clean: only one hyprland variable" "$BASH_BIN" "$JOURNAL_ORIG" "$JOURNAL_RUST" "$JOURNAL_FAKES" \
    XDG_RUNTIME_DIR="$WORK/runtime" -- || true
  mkdir -p "$WORK/runtime-write/hypr/sig"
  ln -sfn /proc/version "$WORK/runtime-write/hypr/sig/hyprland.log"
  compare "journal-clean: unwritable hyprland log" "$BASH_BIN" "$JOURNAL_ORIG" "$JOURNAL_RUST" "$JOURNAL_FAKES" \
    XDG_RUNTIME_DIR="$WORK/runtime-write" HYPRLAND_INSTANCE_SIGNATURE=sig -- || true
fi

# ---------------------------------------------------------------------------
section "pass-2col"
PASS_FAKES=$WORK/fakes/pass
PASS_NOWL=$WORK/fakes/pass-nowl
PASS_NONOTIFY=$WORK/fakes/pass-nonotify
mkdir -p "$PASS_FAKES" "$PASS_NOWL" "$PASS_NONOTIFY"
make_fake "$PASS_FAKES" vicinae '#!/bin/sh
printf "vicinae\n" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf "  %s\n" "$arg" >> "$FAKE_ARGV_LOG"; done
while IFS= read -r line; do printf "%s\n" "$line" >> "$FAKE_DMENU_IN"; done
printf "%s" "${FAKE_SEL:-}"
exit "${FAKE_SEL_CODE:-0}"
'
make_fake "$PASS_FAKES" pass '#!/bin/sh
printf "pass\n" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf "  %s\n" "$arg" >> "$FAKE_ARGV_LOG"; done
case "$1" in
  otp)
    if [ "$2" = "code" ]; then printf "%s" "${FAKE_OTP:-}"; exit "${FAKE_OTP_CODE:-0}"; fi
    exit "${FAKE_OTP_C_CODE:-0}"
    ;;
  show)
    printf "%s" "${FAKE_SHOW:-}"
    exit "${FAKE_SHOW_CODE:-0}"
    ;;
  -c)
    exit "${FAKE_PASS_C_CODE:-0}"
    ;;
esac
exit 0
'
make_fake "$PASS_FAKES" wl-copy '#!/bin/sh
printf "wl-copy\n" >> "$FAKE_ARGV_LOG"
IFS= read -r value || true
printf "%s" "$value" >> "$FAKE_CLIP"
exit "${FAKE_WLCOPY_CODE:-0}"
'
make_fake "$PASS_FAKES" notify-send '#!/bin/sh
printf "notify-send\n" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf "  %s\n" "$arg" >> "$FAKE_ARGV_LOG"; done
exit 0
'
cp -- "$PASS_FAKES/vicinae" "$PASS_FAKES/pass" "$PASS_FAKES/notify-send" "$PASS_NOWL/"
cp -- "$PASS_FAKES/vicinae" "$PASS_FAKES/pass" "$PASS_FAKES/wl-copy" "$PASS_NONOTIFY/"
STORE=$WORK/case/store
mkdir -p "$STORE/dir" "$STORE/.git" "$STORE/nested/.git"
for entry in alpha.gpg dir/beta.gpg .gpg-id .git/secret.gpg nested/.git/inner.gpg "space name.gpg"; do
  printf 'fixture' > "$STORE/$entry"
done
PASS_ORIG=$WORK/originals/pass-2col
PASS_RUST=$BIN_DIR/pass-2col
PASS_PATH="$PASS_FAKES:$SYSTEM_UTILS_PATH"
PASS_NOWL_PATH="$PASS_NOWL:$SYSTEM_UTILS_PATH"
PASS_NONOTIFY_PATH="$PASS_NONOTIFY:$SYSTEM_UTILS_PATH"
if [ -r "$PASS_ORIG" ]; then
  compare "pass-2col: OTP code" "$BASH_BIN" "$PASS_ORIG" "$PASS_RUST" "$PASS_PATH" \
    PASSWORD_STORE_DIR="$STORE" FAKE_SEL=alpha FAKE_OTP=$'123456\nignored\n' -- || true
  compare "pass-2col: password fallback" "$BASH_BIN" "$PASS_ORIG" "$PASS_RUST" "$PASS_PATH" \
    PASSWORD_STORE_DIR="$STORE" FAKE_SEL=dir/beta FAKE_OTP_CODE=1 FAKE_SHOW=$'hunter2\nsecond\n' -- || true
  compare "pass-2col: otpauth guard" "$BASH_BIN" "$PASS_ORIG" "$PASS_RUST" "$PASS_PATH" \
    PASSWORD_STORE_DIR="$STORE" FAKE_SEL=alpha FAKE_OTP= FAKE_SHOW='otpauth://totp/x' FAKE_OTP_C_CODE=1 -- || true
  compare "pass-2col: empty selection" "$BASH_BIN" "$PASS_ORIG" "$PASS_RUST" "$PASS_PATH" \
    PASSWORD_STORE_DIR="$STORE" FAKE_SEL= -- || true
  compare "pass-2col: entries ordering" "$BASH_BIN" "$PASS_ORIG" "$PASS_RUST" "$PASS_PATH" \
    PASSWORD_STORE_DIR="$STORE" FAKE_SEL='space name' FAKE_OTP_CODE=1 FAKE_SHOW='pw' -- || true
  compare "pass-2col: missing store" "$BASH_BIN" "$PASS_ORIG" "$PASS_RUST" "$PASS_PATH" \
    PASSWORD_STORE_DIR="$WORK/case/no-store" -- || true
  compare "pass-2col: selection newlines" "$BASH_BIN" "$PASS_ORIG" "$PASS_RUST" "$PASS_PATH" \
    PASSWORD_STORE_DIR="$STORE" FAKE_SEL=$'alpha\n\n' FAKE_OTP=code -- || true
  compare "pass-2col: no wl-copy" "$BASH_BIN" "$PASS_ORIG" "$PASS_RUST" "$PASS_NOWL_PATH" \
    PASSWORD_STORE_DIR="$STORE" FAKE_SEL=alpha FAKE_OTP=$'654321\n' -- || true
  compare "pass-2col: no notify-send" "$BASH_BIN" "$PASS_ORIG" "$PASS_RUST" "$PASS_NONOTIFY_PATH" \
    PASSWORD_STORE_DIR="$STORE" FAKE_SEL=alpha FAKE_OTP=$'112233\n' -- || true
  compare "pass-2col: vicinae failure" "$BASH_BIN" "$PASS_ORIG" "$PASS_RUST" "$PASS_PATH" \
    PASSWORD_STORE_DIR="$STORE" FAKE_SEL_CODE=3 -- || true
fi

# ---------------------------------------------------------------------------
section "music-highlevel"
MUSIC_FAKES=$WORK/fakes/music
MUSIC_NONE=$WORK/fakes/music-none
mkdir -p "$MUSIC_FAKES" "$MUSIC_NONE"
make_fake "$MUSIC_FAKES" streaming_extractor_music '#!/bin/sh
printf "extractor\n" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf "  %s\n" "$arg" >> "$FAKE_ARGV_LOG"; done
printf "extractor-stdout-noise\n"
printf "extractor-stderr-noise\n" >&2
case "$1" in
  *fail.mp3) exit 3 ;;
  *nofile.mp3) exit 0 ;;
esac
if [ -n "${FAKE_JSON_CONTENT+set}" ]; then
  printf "%s" "$FAKE_JSON_CONTENT" > "$2"
fi
exit 0
'
make_fake "$MUSIC_FAKES" playerctl '#!/bin/sh
printf "playerctl\n" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf "  %s\n" "$arg" >> "$FAKE_ARGV_LOG"; done
printf "%s" "${FAKE_TRACK:-}"
exit "${FAKE_TRACK_CODE:-0}"
'
make_fake "$MUSIC_NONE" playerctl '#!/bin/sh
printf "%s" "${FAKE_TRACK:-}"
'
MUSIC_ORIG=$WORK/originals/music-highlevel
MUSIC_RUST=$BIN_DIR/music-highlevel
if [ -r "$MUSIC_ORIG" ]; then
  MUSIC=$WORK/case/media
  MUSIC_WALK=$WORK/case/media-walk
  mkdir -p "$MUSIC" "$MUSIC_WALK/sub"
  for file in a.mp3 b.flac c.txt 'e space.mp3' fail.mp3 nofile.mp3; do
    printf '' > "$MUSIC/$file"
  done
  for file in b.ogg 'a space.mp3' C.FLAC notes.txt sub/d.wav; do
    printf '' > "$MUSIC_WALK/$file"
  done
  HIGHLEVEL=$(< "$HERE/parity/highlevel.json")
  EDGE=$(< "$HERE/parity/edge.json")
  compare "music-highlevel: help 80" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" COLUMNS=80 -- --help || true
  compare "music-highlevel: help 40" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" COLUMNS=40 -- --help || true
  compare "music-highlevel: help 100" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" COLUMNS=100 -- --help || true
  compare "music-highlevel: unrecognized argument" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" -- --bogus || true
  compare "music-highlevel: invalid int" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" -- --top x || true
  compare "music-highlevel: ambiguous abbreviation" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" -- --t=3 || true
  compare "music-highlevel: ignored explicit argument" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" -- --json=false || true
  compare "music-highlevel: missing option value" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" -- --top -x || true
  compare "music-highlevel: JSON output" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" \
    FAKE_JSON_CONTENT="$HIGHLEVEL" -- --json "$MUSIC/a.mp3" || true
  compare "music-highlevel: human output" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" \
    FAKE_JSON_CONTENT="$HIGHLEVEL" -- "$MUSIC/a.mp3" || true
  compare "music-highlevel: edge values" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" \
    FAKE_JSON_CONTENT="$EDGE" -- --json "$MUSIC/a.mp3" || true
  compare "music-highlevel: top and taxonomies" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" \
    FAKE_JSON_CONTENT="$HIGHLEVEL" -- --json --top 2 "$MUSIC/a.mp3" --taxonomies genre_dortmund tonal_atonal || true
  compare "music-highlevel: directory walk" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" \
    FAKE_JSON_CONTENT="$HIGHLEVEL" -- --json "$MUSIC_WALK" || true
  compare "music-highlevel: explicit non-audio file" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" \
    FAKE_JSON_CONTENT="$HIGHLEVEL" -- --json "$MUSIC/c.txt" || true
  compare "music-highlevel: playerctl fallback" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" \
    FAKE_JSON_CONTENT="$HIGHLEVEL" FAKE_TRACK="file://$MUSIC/e%20space.mp3" -- --json || true
  compare "music-highlevel: missing highlevel" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" \
    FAKE_JSON_CONTENT='{}' -- --json "$MUSIC/a.mp3" || true
  compare "music-highlevel: malformed output" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" \
    FAKE_JSON_CONTENT='not json' -- --json "$MUSIC/a.mp3" || true
  compare "music-highlevel: extractor failure" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" \
    FAKE_JSON_CONTENT="$HIGHLEVEL" -- --json "$MUSIC/fail.mp3" "$MUSIC/a.mp3" || true
  compare "music-highlevel: missing output file" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" \
    -- --json "$MUSIC/nofile.mp3" || true
  compare "music-highlevel: no inputs" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" \
    FAKE_TRACK= -- --json || true
  compare "music-highlevel: no audio files" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" \
    -- /definitely/not/here || true
  compare "music-highlevel: empty taxonomies list" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" \
    FAKE_JSON_CONTENT="$HIGHLEVEL" -- --json --taxonomies= "$MUSIC/a.mp3" || true
  compare_status_only "music-highlevel: missing extractor" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_NONE" \
    -- --json "$MUSIC/a.mp3"
  compare_status_only "music-highlevel: non-object output" "$PYTHON_BIN" "$MUSIC_ORIG" "$MUSIC_RUST" "$MUSIC_FAKES" \
    FAKE_JSON_CONTENT='[]' -- --json "$MUSIC/a.mp3"
fi

# ---------------------------------------------------------------------------
printf '\n%d checks, %d failed\n' "$CHECKS" "$FAILED"
exit "$FAILED"
