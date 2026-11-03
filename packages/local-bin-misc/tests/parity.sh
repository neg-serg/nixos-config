#!/usr/bin/env bash
# Parity harness: run the shipped shell helpers and the Rust ports side by side
# against the same fake external tools, and compare every observable: exit
# status, stdout bytes, stderr bytes, the argv each tool received, the stdio
# the fake read, and the environment the wrapper built.
#
#   tests/parity.sh [--bin-dir DIR] [--originals-dir DIR] [--attached]
#
# Env: CARGO_TARGET_DIR selects the target directory (default: ../target);
#      LOCAL_BIN_MISC_BIN overrides the directory holding the built binaries.
#      LOCAL_BIN_MISC_ORIGINALS overrides the source shell directory.
#
# The fakes are shell scripts first on an otherwise empty PATH; HOME, XDG and
# TMPDIR point into a temporary tree. The harness never creates or removes
# /tmp/nvim.sock: `v`'s fresh-server path is forced with a failing fake `nc`
# (and a fake `rm`, so even the original cannot unlink anything), and the
# attached-path cases run only with --attached, which the caller should pass
# only while that socket really exists.
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/.." && pwd)
REPO=$(cd -- "$ROOT/../.." && pwd)
ORIGINALS=${LOCAL_BIN_MISC_ORIGINALS:-$REPO/packages/local-bin/bin}
BIN_DIR=${LOCAL_BIN_MISC_BIN:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
ATTACHED=0

while [ $# -gt 0 ]; do
  case "$1" in
    --bin-dir)
      BIN_DIR=$2
      shift 2
      ;;
    --originals-dir)
      ORIGINALS=$2
      shift 2
      ;;
    --attached)
      ATTACHED=1
      shift
      ;;
    -h | --help)
      sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "parity: unknown argument '$1'" >&2
      exit 2
      ;;
  esac
done

BASH_BIN=$(command -v bash)
SH_BIN=$(command -v sh)
for tool in "$BASH_BIN" "$SH_BIN"; do
  [ -n "$tool" ] || {
    echo "parity: bash and sh are required" >&2
    exit 2
  }
done
for tool in dirname cat sed paste diff mktemp cp ln chmod; do
  command -v "$tool" > /dev/null 2>&1 || {
    echo "parity: missing required utility: $tool" >&2
    exit 2
  }
done

WORK=$(mktemp -d "${TMPDIR:-/tmp}/local-bin-misc-parity.XXXXXX")
cleanup() { rm -rf -- "$WORK"; }
trap cleanup EXIT

mkdir -p "$WORK/originals" "$WORK/home" "$WORK/tmp" "$WORK/case" "$WORK/fakes" "$WORK/utils"
printf '' > "$WORK/stdin"

# --- originals -------------------------------------------------------------
# Sources are copied next to `_localbin.sh`, so `dirname "$0"` finds the helper
# even when the working tree no longer carries the scripts (recovered from the
# last commit that had them).
recover() {
  local name=$1
  local source=$ORIGINALS/$name
  if [ -r "$source" ]; then
    cp -- "$source" "$WORK/originals/$name"
    return 0
  fi
  local rel="packages/local-bin/bin/$name"
  if git -C "$REPO" cat-file -e "HEAD:$rel" 2> /dev/null; then
    git -C "$REPO" show "HEAD:$rel" > "$WORK/originals/$name"
    return 0
  fi
  # The file may already be deleted on HEAD: take it from the parent of the
  # commit that removed it.
  local revision
  revision=$(git -C "$REPO" log --all --format=%H -1 --diff-filter=D -- "$rel" 2> /dev/null || true)
  [ -n "$revision" ] || return 1
  git -C "$REPO" show "${revision}^:$rel" > "$WORK/originals/$name" 2> /dev/null || return 1
  return 0
}

for name in pb any v sclang-pwj renoise-pwj; do
  recover "$name" || {
    echo "parity: cannot find the original $name" >&2
    exit 2
  }
done
recover _localbin.sh || {
  echo "parity: cannot find the original _localbin.sh" >&2
  exit 2
}

# The sandbox of a Nix build has no /etc/profile, and bash aborts a
# non-interactive script when `.` cannot open its file. Replace only that line
# with the `:` builtin in the copied original so the rest of `v` (including the
# line numbers in its diagnostics) runs unchanged. Host runs keep the file.
if [ ! -r /etc/profile ]; then
  sed -i 's|^\. /etc/profile$|:|' "$WORK/originals/v"
  printf 'note: /etc/profile is absent; v runs with the profile source stubbed to ":"\n'
fi

for program in pb any v sclang-pwj renoise-pwj; do
  [ -x "$BIN_DIR/$program" ] || {
    echo "parity: binary not executable: $BIN_DIR/$program" >&2
    echo "parity: run cargo build --locked first, or pass --bin-dir DIR" >&2
    exit 2
  }
done

# Utilities the shell originals call for their own housekeeping (usage text,
# `dirname`, the PID join). None of them is a tool under test.
for tool in dirname cat sed paste; do
  ln -s "$(command -v "$tool")" "$WORK/utils/$tool"
done

FAILED=0
CHECKS=0
SKIPPED=0
pass() {
  CHECKS=$((CHECKS + 1))
  printf 'PASS  %s\n' "$1"
}
fail() {
  CHECKS=$((CHECKS + 1))
  FAILED=1
  printf 'FAIL  %s\n' "$1" >&2
}
skip() {
  SKIPPED=$((SKIPPED + 1))
  printf 'SKIP  %s\n' "$1"
}
section() { printf '\n== %s ==\n' "$1"; }

make_fake() {
  local directory=$1 name=$2 body=$3
  printf '%s' "$body" > "$directory/$name"
  chmod +x "$directory/$name"
}

artifact() {
  if [ -f "$1" ]; then cat -- "$1"; fi
}

normalize() {
  local original=$1 rust=$2
  # The Rust port does not source /etc/profile (documented deviation: a
  # compiled binary cannot evaluate shell state). In a build sandbox that file
  # does not exist and bash reports the failed source; drop only that exact
  # line so the sandbox run can still compare every other observable.
  sed -E \
    -e "s|$original|PROG|g" \
    -e "s|$rust|PROG|g" \
    -e "s|$WORK|WORK|g" \
    -e '/^PROG: line 5: \/etc\/profile: No such file or directory$/d'
}

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
    XDG_CACHE_HOME="$WORK/home/.cache"
    XDG_CONFIG_HOME="$WORK/home/.config"
    XDG_DATA_HOME="$WORK/home/.local/share"
    XDG_STATE_HOME="$WORK/home/.local/state"
    LANG=C
    LC_ALL=C
    # Keep `. /etc/profile` from replacing PATH with the system one; a normal
    # user session already exports this guard.
    __NIXOS_SET_ENVIRONMENT_DONE=1
    __ETC_PROFILE_DONE=1
  )
  assignments+=("${overrides[@]}")
  assignments+=(
    FAKE_ARGV_LOG="$WORK/$side.argv"
    FAKE_ENV_LOG="$WORK/$side.env"
    FAKE_STDIN_LOG="$WORK/$side.stdin"
  )
  if [ "$interpreter" = direct ]; then
    env -i "${assignments[@]}" "$program" "$@"
  else
    env -i "${assignments[@]}" "$interpreter" "$program" "$@"
  fi
}

STDIN_PAYLOAD=""
with_stdin() {
  STDIN_PAYLOAD=$1
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
  local -a arguments=("$@")

  printf '%s' "$STDIN_PAYLOAD" > "$WORK/stdin"
  STDIN_PAYLOAD=""

  rm -f "$WORK"/o.out "$WORK"/o.err "$WORK"/o.argv "$WORK"/o.env "$WORK"/o.stdin \
    "$WORK"/r.out "$WORK"/r.err "$WORK"/r.argv "$WORK"/r.env "$WORK"/r.stdin

  local original_status rust_status
  set +e
  (cd "$WORK/case" && invoke o "$interpreter" "$original" "$fake_path" "${overrides[@]}" -- "${arguments[@]}") \
    < "$WORK/stdin" > "$WORK/o.out" 2> "$WORK/o.err"
  original_status=$?
  (cd "$WORK/case" && invoke r direct "$rust" "$fake_path" "${overrides[@]}" -- "${arguments[@]}") \
    < "$WORK/stdin" > "$WORK/r.out" 2> "$WORK/r.err"
  rust_status=$?
  set -e

  local ok=1 detail=""
  if [ "$original_status" -ne "$rust_status" ]; then
    ok=0
    detail+="  exit: original=$original_status rust=$rust_status"$'\n'
  fi
  local stream o_file r_file output
  for stream in out err argv env stdin; do
    o_file=$WORK/o.$stream
    r_file=$WORK/r.$stream
    if [ ! -f "$o_file" ] && [ ! -f "$r_file" ]; then
      continue
    fi
    if [ "$stream" = out ] || [ "$stream" = err ]; then
      output=$(diff -u \
        <(artifact "$o_file" | normalize "$original" "$rust") \
        <(artifact "$r_file" | normalize "$original" "$rust") || true)
    else
      output=$(diff -u <(artifact "$o_file") <(artifact "$r_file") || true)
    fi
    if [ -n "$output" ]; then
      ok=0
      detail+="  $stream:"$'\n'"$output"$'\n'
    fi
  done

  if [ "$ok" = 1 ]; then
    pass "$label"
  else
    fail "$label"
    printf '%s' "$detail" >&2
  fi
}

# ---------------------------------------------------------------------------
section "originals"
printf 'originals: %s\n' "$ORIGINALS"
printf 'binaries:  %s\n' "$BIN_DIR"
printf 'attached:  %s\n' "$([ "$ATTACHED" = 1 ] && echo enabled || echo disabled)"

# ---------------------------------------------------------------------------
section "pb"
PB_FAKES=$WORK/fakes/pb
PB_NO_CURL=$WORK/fakes/pb-no-curl
mkdir -p "$PB_FAKES" "$PB_NO_CURL"
make_fake "$PB_FAKES" curl '#!/bin/sh
printf "curl\n" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf "  %s\n" "$arg" >> "$FAKE_ARGV_LOG"; done
printf "stdin\n" >> "$FAKE_ARGV_LOG"
while IFS= read -r line || [ -n "$line" ]; do printf "  %s\n" "$line" >> "$FAKE_STDIN_LOG"; done 2>/dev/null
printf "%s" "${FAKE_OUT:-}"
printf "%s" "${FAKE_ERR:-}" >&2
exit "${FAKE_CODE:-0}"
'
printf 'payload-data\nsecond-line\n' > "$WORK/case/pb-payload.txt"
ln -sfn "$WORK/case/pb-payload.txt" "$WORK/case/pb-payload-link"
PB_ORIG=$WORK/originals/pb
PB_RUST=$BIN_DIR/pb
compare "pb: no arguments (usage)" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- || true
compare "pb: --help" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- --help || true
compare "pb: help word" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- help || true
compare "pb: question mark" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- '?' || true
compare "pb: unknown service" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- bogus || true
compare "pb: unknown service without curl" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_NO_CURL:$WORK/utils" -- bogus || true
compare "pb: temp with a file" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- temp pb-payload.txt || true
compare "pb: tmp alias" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- tmp pb-payload.txt || true
compare "pb: temp.sh alias" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- temp.sh pb-payload.txt || true
compare "pb: iotek" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- iotek pb-payload.txt || true
compare "pb: iopaste" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- iopaste pb-payload.txt || true
compare "pb: p.iotek.org" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- p.iotek.org pb-payload.txt || true
compare "pb: iop prefix" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- iop-anything pb-payload.txt || true
compare "pb: uguu" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- uguu pb-payload.txt || true
compare "pb: uguu.se" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- uguu.se pb-payload.txt || true
compare "pb: u prefix" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- upload pb-payload.txt || true
compare "pb: catbox" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- catbox pb-payload.txt || true
compare "pb: catbox.moe" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- catbox.moe pb-payload.txt || true
compare "pb: cat prefix" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- cat-anything pb-payload.txt || true
compare "pb: custom UA" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" UA=custom-agent/1.0 -- temp pb-payload.txt || true
compare "pb: empty UA uses the default" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" UA= -- temp pb-payload.txt || true
with_stdin 'stream-one
stream-two
'
compare "pb: default stdin" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- temp || true
with_stdin 'empty-second-arg
'
compare "pb: empty second argument means stdin" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- temp '' || true
compare "pb: missing file" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- temp missing.txt || true
compare "pb: directory argument" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- temp . || true
compare "pb: dash without the file" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- temp - || true
printf 'dash-file-data\n' > "$WORK/case/-"
compare "pb: dash with a literal file" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- temp - || true
rm -f "$WORK/case/-"
compare "pb: curl status and streams" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" FAKE_OUT=uploaded FAKE_ERR=problem FAKE_CODE=7 -- temp pb-payload.txt || true
compare "pb: missing curl" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_NO_CURL:$WORK/utils" -- temp pb-payload.txt || true
compare "pb: extra arguments ignored" "$SH_BIN" "$PB_ORIG" "$PB_RUST" "$PB_FAKES:$WORK/utils" -- temp pb-payload.txt ignored extra || true

# ---------------------------------------------------------------------------
section "any"
ANY_FAKES=$WORK/fakes/any
ANY_NO_PGREP=$WORK/fakes/any-no-pgrep
ANY_NO_PS=$WORK/fakes/any-no-ps
mkdir -p "$ANY_FAKES" "$ANY_NO_PGREP" "$ANY_NO_PS"
make_fake "$ANY_FAKES" pgrep '#!/bin/sh
printf "pgrep\n" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf "  %s\n" "$arg" >> "$FAKE_ARGV_LOG"; done
printf "%s" "${FAKE_PGREP_ERR:-}" >&2
printf "%s" "${FAKE_PGREP_OUT:-}"
exit "${FAKE_PGREP_CODE:-0}"
'
make_fake "$ANY_FAKES" ps '#!/bin/sh
printf "ps\n" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf "  %s\n" "$arg" >> "$FAKE_ARGV_LOG"; done
printf "%s" "${FAKE_PS_OUT:-}"
printf "%s" "${FAKE_PS_ERR:-}" >&2
exit "${FAKE_PS_CODE:-0}"
'
cp -- "$ANY_FAKES/ps" "$ANY_NO_PGREP/ps"
cp -- "$ANY_FAKES/pgrep" "$ANY_NO_PS/pgrep"
ANY_ORIG=$WORK/originals/any
ANY_RUST=$BIN_DIR/any
compare "any: one match" "$SH_BIN" "$ANY_ORIG" "$ANY_RUST" "$ANY_FAKES:$WORK/utils" FAKE_PGREP_OUT='11
' -- firefox || true
compare "any: several PIDs join with commas" "$SH_BIN" "$ANY_ORIG" "$ANY_RUST" "$ANY_FAKES:$WORK/utils" FAKE_PGREP_OUT='11
22
' -- firefox || true
compare "any: user options" "$SH_BIN" "$ANY_ORIG" "$ANY_RUST" "$ANY_FAKES:$WORK/utils" FAKE_PGREP_OUT='7
' -- -u neg -x sshd || true
compare "any: no arguments" "$SH_BIN" "$ANY_ORIG" "$ANY_RUST" "$ANY_FAKES:$WORK/utils" FAKE_PGREP_OUT='3
' -- || true
compare "any: no matches" "$SH_BIN" "$ANY_ORIG" "$ANY_RUST" "$ANY_FAKES:$WORK/utils" -- missing || true
compare "any: pgrep stderr is discarded" "$SH_BIN" "$ANY_ORIG" "$ANY_RUST" "$ANY_FAKES:$WORK/utils" FAKE_PGREP_OUT='5
' FAKE_PGREP_ERR=pgrep-noise -- foo || true
compare "any: pgrep failure keeps output" "$SH_BIN" "$ANY_ORIG" "$ANY_RUST" "$ANY_FAKES:$WORK/utils" FAKE_PGREP_OUT='6
' FAKE_PGREP_CODE=2 -- foo || true
compare "any: pgrep failure without output" "$SH_BIN" "$ANY_ORIG" "$ANY_RUST" "$ANY_FAKES:$WORK/utils" FAKE_PGREP_CODE=2 -- foo || true
compare "any: blank lines join like paste" "$SH_BIN" "$ANY_ORIG" "$ANY_RUST" "$ANY_FAKES:$WORK/utils" FAKE_PGREP_OUT='1
2


' -- x || true
compare "any: -h usage" "$SH_BIN" "$ANY_ORIG" "$ANY_RUST" "$ANY_FAKES:$WORK/utils" -- -h || true
compare "any: ? usage" "$SH_BIN" "$ANY_ORIG" "$ANY_RUST" "$ANY_FAKES:$WORK/utils" -- '?' || true
compare "any: missing pgrep" "$SH_BIN" "$ANY_ORIG" "$ANY_RUST" "$ANY_NO_PGREP:$WORK/utils" -- x || true
compare "any: missing ps" "$SH_BIN" "$ANY_ORIG" "$ANY_RUST" "$ANY_NO_PS:$WORK/utils" FAKE_PGREP_OUT='5
' -- x || true
compare "any: ps status and streams" "$SH_BIN" "$ANY_ORIG" "$ANY_RUST" "$ANY_FAKES:$WORK/utils" FAKE_PGREP_OUT='4
' FAKE_PS_OUT=ps-out FAKE_PS_ERR=ps-err FAKE_PS_CODE=7 -- x || true

# ---------------------------------------------------------------------------
section "v (fresh server, fake nc always fails)"
V_FAKES=$WORK/fakes/v
V_NO_NC=$WORK/fakes/v-no-nc
V_NO_NVIM=$WORK/fakes/v-no-nvim
V_NO_RM=$WORK/fakes/v-no-rm
mkdir -p "$V_FAKES" "$V_NO_NC" "$V_NO_NVIM" "$V_NO_RM"
make_fake "$V_FAKES" nc '#!/bin/sh
printf "nc\n" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf "  %s\n" "$arg" >> "$FAKE_ARGV_LOG"; done
printf "%s" "${FAKE_NC_OUT:-}"
printf "%s" "${FAKE_NC_ERR:-}" >&2
exit "${FAKE_NC_CODE:-0}"
'
make_fake "$V_FAKES" nvr '#!/bin/sh
printf "nvr\n" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf "  %s\n" "$arg" >> "$FAKE_ARGV_LOG"; done
printf "nvr NVIM_APPNAME=[%s] set=%s\n" "${NVIM_APPNAME-}" "${NVIM_APPNAME+set}" >> "$FAKE_ENV_LOG"
printf "%s" "${FAKE_OUT:-}"
printf "%s" "${FAKE_ERR:-}" >&2
exit "${FAKE_CODE:-0}"
'
make_fake "$V_FAKES" hyprctl '#!/bin/sh
printf "hyprctl\n" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf "  %s\n" "$arg" >> "$FAKE_ARGV_LOG"; done
printf "%s" "${FAKE_OUT:-}"
printf "%s" "${FAKE_ERR:-}" >&2
exit "${FAKE_CODE:-0}"
'
make_fake "$V_FAKES" rm '#!/bin/sh
printf "rm\n" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf "  %s\n" "$arg" >> "$FAKE_ARGV_LOG"; done
exit "${FAKE_CODE:-0}"
'
make_fake "$V_FAKES" nvim '#!/bin/sh
printf "nvim\n" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf "  %s\n" "$arg" >> "$FAKE_ARGV_LOG"; done
printf "nvim NVIM_APPNAME=[%s] set=%s\n" "${NVIM_APPNAME-}" "${NVIM_APPNAME+set}" >> "$FAKE_ENV_LOG"
printf "%s" "${FAKE_OUT:-}"
printf "%s" "${FAKE_ERR:-}" >&2
exit "${FAKE_CODE:-0}"
'
cp -- "$V_FAKES/nvr" "$V_FAKES/hyprctl" "$V_FAKES/rm" "$V_FAKES/nvim" "$V_NO_NC/"
cp -- "$V_FAKES/nc" "$V_FAKES/nvr" "$V_FAKES/hyprctl" "$V_FAKES/rm" "$V_NO_NVIM/"
cp -- "$V_FAKES/nc" "$V_FAKES/nvr" "$V_FAKES/hyprctl" "$V_FAKES/nvim" "$V_NO_RM/"
V_ORIG=$WORK/originals/v
V_RUST=$BIN_DIR/v
compare "v: fresh server (nc fails)" "$SH_BIN" "$V_ORIG" "$V_RUST" "$V_FAKES:$WORK/utils" FAKE_NC_CODE=1 FAKE_NVIM_OUT=nvim-out FAKE_NVIM_ERR=nvim-err FAKE_NVIM_CODE=3 -- file -h || true
compare "v: fresh server without arguments" "$SH_BIN" "$V_ORIG" "$V_RUST" "$V_FAKES:$WORK/utils" FAKE_NC_CODE=1 -- || true
compare "v: nc output is discarded" "$SH_BIN" "$V_ORIG" "$V_RUST" "$V_FAKES:$WORK/utils" FAKE_NC_CODE=1 FAKE_NC_OUT=nc-out FAKE_NC_ERR=nc-err -- x || true
compare "v: missing nc" "$SH_BIN" "$V_ORIG" "$V_RUST" "$V_NO_NC:$WORK/utils" FAKE_NC_CODE=1 -- x || true
compare "v: missing nvim" "$SH_BIN" "$V_ORIG" "$V_RUST" "$V_NO_NVIM:$WORK/utils" FAKE_NC_CODE=1 -- x || true
compare "v: missing rm" "$SH_BIN" "$V_ORIG" "$V_RUST" "$V_NO_RM:$WORK/utils" FAKE_NC_CODE=1 -- x || true

if [ "$ATTACHED" = 1 ]; then
  section "v (attached)"
  V_NO_NVR=$WORK/fakes/v-no-nvr
  V_NO_HYPRCTL=$WORK/fakes/v-no-hyprctl
  mkdir -p "$V_NO_NVR" "$V_NO_HYPRCTL"
  cp -- "$V_FAKES/nc" "$V_FAKES/hyprctl" "$V_FAKES/rm" "$V_FAKES/nvim" "$V_NO_NVR/"
  cp -- "$V_FAKES/nc" "$V_FAKES/nvr" "$V_FAKES/rm" "$V_FAKES/nvim" "$V_NO_HYPRCTL/"
  compare "v: attached without arguments" "$SH_BIN" "$V_ORIG" "$V_RUST" "$V_FAKES:$WORK/utils" FAKE_NC_CODE=0 -- || true
  compare "v: attached with arguments" "$SH_BIN" "$V_ORIG" "$V_RUST" "$V_FAKES:$WORK/utils" FAKE_NC_CODE=0 -- file -h || true
  compare "v: attached nvr failure" "$SH_BIN" "$V_ORIG" "$V_RUST" "$V_FAKES:$WORK/utils" FAKE_NC_CODE=0 FAKE_OUT=nvr-out FAKE_ERR=nvr-err FAKE_CODE=3 -- file || true
  compare "v: attached hyprctl failure" "$SH_BIN" "$V_ORIG" "$V_RUST" "$V_FAKES:$WORK/utils" FAKE_NC_CODE=0 FAKE_HYPRCTL_ERR=hypr-err -- file || true
  compare "v: attached missing nvr" "$SH_BIN" "$V_ORIG" "$V_RUST" "$V_NO_NVR:$WORK/utils" FAKE_NC_CODE=0 -- file || true
  compare "v: attached missing hyprctl" "$SH_BIN" "$V_ORIG" "$V_RUST" "$V_NO_HYPRCTL:$WORK/utils" FAKE_NC_CODE=0 -- file || true
else
  for label in "v: attached without arguments" "v: attached with arguments" \
    "v: attached nvr failure" "v: attached hyprctl failure" \
    "v: attached missing nvr" "v: attached missing hyprctl"; do
    skip "$label (pass --attached only while /tmp/nvim.sock exists)"
  done
fi

# ---------------------------------------------------------------------------
section "sclang-pwj / renoise-pwj"
WRAP_FAKES=$WORK/fakes/wrappers
WRAP_NO_PWJACK=$WORK/fakes/wrappers-no-pwjack
WRAP_NO_RENOISE=$WORK/fakes/wrappers-no-renoise
mkdir -p "$WRAP_FAKES" "$WRAP_NO_PWJACK" "$WRAP_NO_RENOISE"
make_fake "$WRAP_FAKES" pw-jack '#!/bin/sh
printf "pw-jack\n" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf "  %s\n" "$arg" >> "$FAKE_ARGV_LOG"; done
printf "ld=[%s] set=%s\n" "${LD_LIBRARY_PATH-}" "${LD_LIBRARY_PATH+set}" >> "$FAKE_ENV_LOG"
while IFS= read -r line || [ -n "$line" ]; do printf "stdin=[%s]\n" "$line" >> "$FAKE_ENV_LOG"; done
printf "%s" "${FAKE_OUT:-}"
printf "%s" "${FAKE_ERR:-}" >&2
exit "${FAKE_CODE:-0}"
'
make_fake "$WRAP_FAKES" renoise '#!/bin/sh
printf "renoise\n" >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf "  %s\n" "$arg" >> "$FAKE_ARGV_LOG"; done
printf "ld=[%s] set=%s\n" "${LD_LIBRARY_PATH-}" "${LD_LIBRARY_PATH+set}" >> "$FAKE_ENV_LOG"
while IFS= read -r line || [ -n "$line" ]; do printf "stdin=[%s]\n" "$line" >> "$FAKE_ENV_LOG"; done
printf "%s" "${FAKE_OUT:-}"
printf "%s" "${FAKE_ERR:-}" >&2
exit "${FAKE_CODE:-0}"
'
cp -- "$WRAP_FAKES/renoise" "$WRAP_NO_PWJACK/"
cp -- "$WRAP_FAKES/pw-jack" "$WRAP_NO_RENOISE/"
SCLANG_ORIG=$WORK/originals/sclang-pwj
SCLANG_RUST=$BIN_DIR/sclang-pwj
RENOISE_ORIG=$WORK/originals/renoise-pwj
RENOISE_RUST=$BIN_DIR/renoise-pwj
compare "sclang-pwj: no arguments" "$BASH_BIN" "$SCLANG_ORIG" "$SCLANG_RUST" "$WRAP_FAKES" -- || true
compare "sclang-pwj: argv passthrough" "$BASH_BIN" "$SCLANG_ORIG" "$SCLANG_RUST" "$WRAP_FAKES" FAKE_OUT=editor-out FAKE_ERR=editor-err FAKE_CODE=7 -- -x --help 'a b' || true
compare "sclang-pwj: LD_LIBRARY_PATH unset" "$BASH_BIN" "$SCLANG_ORIG" "$SCLANG_RUST" "$WRAP_FAKES" -- || true
compare "sclang-pwj: LD_LIBRARY_PATH empty" "$BASH_BIN" "$SCLANG_ORIG" "$SCLANG_RUST" "$WRAP_FAKES" LD_LIBRARY_PATH= -- || true
compare "sclang-pwj: LD_LIBRARY_PATH set" "$BASH_BIN" "$SCLANG_ORIG" "$SCLANG_RUST" "$WRAP_FAKES" LD_LIBRARY_PATH=/custom/lib -- || true
with_stdin 'line-a
line-b
'
compare "sclang-pwj: stdin passthrough" "$BASH_BIN" "$SCLANG_ORIG" "$SCLANG_RUST" "$WRAP_FAKES" -- || true
compare "sclang-pwj: missing pw-jack" "$BASH_BIN" "$SCLANG_ORIG" "$SCLANG_RUST" "$WRAP_NO_PWJACK" -- || true
compare "renoise-pwj: argv passthrough" "$BASH_BIN" "$RENOISE_ORIG" "$RENOISE_RUST" "$WRAP_FAKES" FAKE_OUT=renoise-out FAKE_ERR=renoise-err FAKE_CODE=3 -- -h song.xrns || true
compare "renoise-pwj: inherited environment" "$BASH_BIN" "$RENOISE_ORIG" "$RENOISE_RUST" "$WRAP_FAKES" LD_LIBRARY_PATH=/keep/me -- || true
with_stdin 'payload
'
compare "renoise-pwj: stdin passthrough" "$BASH_BIN" "$RENOISE_ORIG" "$RENOISE_RUST" "$WRAP_FAKES" LD_LIBRARY_PATH=/keep/me -- || true
compare "renoise-pwj: missing renoise" "$BASH_BIN" "$RENOISE_ORIG" "$RENOISE_RUST" "$WRAP_NO_RENOISE" -- || true

# ---------------------------------------------------------------------------
printf '\n%d checks, %d failed, %d skipped\n' "$CHECKS" "$FAILED" "$SKIPPED"
exit "$FAILED"
