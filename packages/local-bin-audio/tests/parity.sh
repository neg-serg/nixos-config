#!/usr/bin/env bash
# Parity harness: run the shipped shell scripts and the Rust ports side by side
# against the same fake external tools, then compare every observable: exit
# code, stdout, stderr, the argv each tool received, and the files both sides
# write.
#
#   tests/parity.sh [--bin-dir DIR] [--tool NAME] [--list] [--verbose]
#
# Env:
#   LOCAL_BIN_AUDIO_BIN   directory with the released binaries (default:
#                         ${CARGO_TARGET_DIR:-target}/debug)
#   PARITY_SYSTEM_BIN     directory with the real coreutils (default:
#                         /run/current-system/sw/bin)
#
# The fakes are /bin/sh scripts first on PATH; HOME, TMPDIR, XDG_RUNTIME_DIR and
# every fake's state file live in a per-side temporary tree. Text filters the
# ports moved in-process (awk, sed, grep, sort, cut, head, wc, tr, dirname) are
# the real host tools for the shell side and native code for the Rust side; they
# are not compared as tool calls, only through their effect. `find`, `xargs`,
# `mkdir`, `mv` and `cp` stay subprocesses on both sides, so they are real host
# tools too. Only the domain tools (PipeWire/ALSA/Renoise/player/browser tools)
# are faked, and their argv logs are compared exactly.
set -uo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/.." && pwd)
REPO=$(cd -- "$ROOT/../.." && pwd)
ORIGINALS=$REPO/packages/local-bin/bin
SYSTEM_BIN=${PARITY_SYSTEM_BIN:-/run/current-system/sw/bin}
BIN_DIR=${LOCAL_BIN_AUDIO_BIN:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}

TOOL_FILTER=
LIST_ONLY=0
VERBOSE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --bin-dir)
      BIN_DIR=$2
      shift 2
      ;;
    --tool)
      TOOL_FILTER=$2
      shift 2
      ;;
    --list)
      LIST_ONLY=1
      shift
      ;;
    --verbose)
      VERBOSE=1
      shift
      ;;
    *)
      echo "parity: unknown argument '$1'" >&2
      exit 2
      ;;
  esac
done

BASH_BIN=$(command -v bash)
PYTHON_BIN=$(command -v python3)
JQ_BIN=$(command -v jq)

WORK=$(mktemp -d "${TMPDIR:-/tmp}/local-bin-audio-parity.XXXXXX")
cleanup() { rm -rf -- "$WORK"; }
trap cleanup EXIT

mkdir -p "$WORK/domain" "$WORK/utils" "$WORK/originals"

# Real utilities used by both sides (shell pipelines for the original, kept
# subprocesses for the port). Symlinked so the fakes stay the only other
# executables on PATH.
for tool in find xargs mkdir mv cp sort head cut wc tr dirname sed awk grep diff cat; do
  ln -s "$SYSTEM_BIN/$tool" "$WORK/utils/$tool"
done
[ -n "$PYTHON_BIN" ] && ln -s "$PYTHON_BIN" "$WORK/utils/python3"
[ -n "$JQ_BIN" ] && ln -s "$JQ_BIN" "$WORK/utils/jq"

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

selected() {
  [ -z "$TOOL_FILTER" ] || [ "$TOOL_FILTER" = "$1" ]
}

# Recover an original that the working tree no longer carries (the last
# committed revision before its deletion).
recover() {
  local name=$1
  if [ -r "$ORIGINALS/$name" ]; then
    cp -- "$ORIGINALS/$name" "$WORK/originals/$name"
    return 0
  fi
  local rel="packages/local-bin/bin/$name"
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

# Every domain fake starts with this logger: one line per invocation,
# "tool<TAB>arg<TAB>arg...".
log_prelude() {
  local name=$1
  # One write per invocation: background fakes (sc-live, xargs children) log
  # concurrently, and a multi-printf prelude would interleave their records.
  printf '#!/bin/sh\n'
  printf 'line="%s"\n' "$name"
  printf 'for arg in "$@"; do line="$line\t$arg"; done\n'
  printf 'printf "%%s\\n" "$line" >> "$FAKE_ARGV_LOG"\n'
}

domain_fake() {
  local name=$1 body=$2
  {
    log_prelude "$name"
    printf '%s\n' "$body"
  } > "$WORK/domain/$name"
  chmod +x "$WORK/domain/$name"
}

# fake_into DIR NAME BODY: a logging fake in an arbitrary directory.
fake_into() {
  local directory=$1 name=$2 body=$3
  mkdir -p "$directory"
  {
    log_prelude "$name"
    printf '%s\n' "$body"
  } > "$directory/$name"
  chmod +x "$directory/$name"
}

reset_side() {
  local side=$1
  rm -rf -- "$WORK/${side:?}"
  mkdir -p "$WORK/$side/home" "$WORK/$side/tmp" "$WORK/$side/run" "$WORK/$side/case"
  : > "$WORK/$side.argv"
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
    PATH="$fake_path:$WORK/utils"
    HOME="$WORK/$side/home"
    TMPDIR="$WORK/$side/tmp"
    XDG_RUNTIME_DIR="$WORK/$side/run"
    LANG=C
    LC_ALL=C
    PWD="$WORK/$side/case"
    FAKE_ARGV_LOG="$WORK/$side.argv"
  )
  assignments+=("${overrides[@]}")
  cd "$WORK/$side/case" || return 1
  if [ "$interpreter" = direct ]; then
    env -i "${assignments[@]}" "$program" "$@"
  else
    env -i "${assignments[@]}" "$interpreter" "$program" "$@"
  fi
}

artifact() {
  if [ -f "$1" ]; then cat -- "$1"; fi
}

wait_quiet() {
  local file=$1
  local previous=-1 size=
  local rounds=0
  while [ "$rounds" -lt 40 ]; do
    size=$(wc -c < "$file" 2> /dev/null || echo 0)
    if [ "$size" = "$previous" ]; then
      rounds=$((rounds + 1))
      [ "$rounds" -ge 5 ] && return 0
    else
      rounds=0
      previous=$size
    fi
    sleep 0.05
  done
}

normalize() {
  local side=$1 name=$2
  sed -E \
    -e "s|$WORK/originals/$name|PROG|g" \
    -e "s|$BIN_DIR/$name|PROG|g" \
    -e "s|$WORK/$side|SIDE|g"
}

SETUP=
SORT_LOG=0

# compare label interpreter original-name rust-name fake-path [ENV=VALUE ...] -- args...
compare() {
  local label=$1 interpreter=$2 name=$3 fake_path=$4
  shift 4
  local -a overrides=()
  while [ "${1:-}" != "--" ]; do
    overrides+=("$1")
    shift
  done
  shift
  local -a args=("$@")

  local original=$WORK/originals/$name
  local rust=$BIN_DIR/$name
  reset_side o
  reset_side r
  if [ -n "$SETUP" ]; then
    "$SETUP" "$WORK/o/home" "$WORK/o/case"
    "$SETUP" "$WORK/r/home" "$WORK/r/case"
  fi

  local original_status rust_status
  set +e
  invoke o "$interpreter" "$original" "$fake_path" "${overrides[@]}" -- "${args[@]}" \
    > "$WORK/o.out" 2> "$WORK/o.err"
  original_status=$?
  invoke r direct "$rust" "$fake_path" "${overrides[@]}" -- "${args[@]}" \
    > "$WORK/r.out" 2> "$WORK/r.err"
  rust_status=$?
  set -e
  wait_quiet "$WORK/o.argv"
  wait_quiet "$WORK/r.argv"
  if [ "$SORT_LOG" = 1 ]; then
    sort -o "$WORK/o.argv" "$WORK/o.argv"
    sort -o "$WORK/r.argv" "$WORK/r.argv"
  fi

  local ok=1 detail=""
  if [ "$original_status" -ne "$rust_status" ]; then
    ok=0
    detail+="  exit: original=$original_status rust=$rust_status"$'\n'
  fi
  local stream
  for stream in out err argv; do
    local o_file r_file
    case "$stream" in
      out) o_file=$WORK/o.out r_file=$WORK/r.out ;;
      err) o_file=$WORK/o.err r_file=$WORK/r.err ;;
      argv) o_file=$WORK/o.argv r_file=$WORK/r.argv ;;
    esac
    local diff_output
    if ! diff_output=$(diff -u \
      <(artifact "$o_file" | normalize o "$name") \
      <(artifact "$r_file" | normalize r "$name")); then
      ok=0
      detail+="  $stream:"$'\n'"$diff_output"$'\n'
    fi
  done

  if [ "$ok" = 1 ]; then
    pass "$label"
  else
    fail "$label"
    printf '%s' "$detail" >&2
    if [ "$VERBOSE" = 1 ]; then
      printf '  original stdout:\n' >&2
      sed 's/^/    /' "$WORK/o.out" >&2
      printf '  rust stdout:\n' >&2
      sed 's/^/    /' "$WORK/r.out" >&2
    fi
  fi
  SETUP=
  SORT_LOG=0
}

# compare_home label RELPATH...: byte-compare files written under HOME.
compare_home() {
  local label=$1
  shift
  local ok=1 relative
  for relative in "$@"; do
    if ! diff -u "$WORK/o/home/$relative" "$WORK/r/home/$relative" > /dev/null 2>&1; then
      ok=0
      printf 'FAIL  %s: home/%s differs\n' "$label" "$relative" >&2
      diff -u "$WORK/o/home/$relative" "$WORK/r/home/$relative" >&2 || true
    fi
  done
  if [ "$ok" = 1 ]; then
    pass "$label (artifacts)"
  else
    fail "$label (artifacts)"
  fi
}

# compare_home_norm label RELPATH: byte-compare after path normalisation.
compare_home_norm() {
  local label=$1 name=$2 relative=$3
  local original rust
  original=$(normalize o "$name" < "$WORK/o/home/$relative")
  rust=$(normalize r "$name" < "$WORK/r/home/$relative")
  if [ "$original" = "$rust" ]; then
    pass "$label (artifacts)"
  else
    fail "$label (artifacts)"
    diff -u <(printf '%s\n' "$original") <(printf '%s\n' "$rust") >&2 || true
  fi
}

# compare_case label RELPATH...: byte-compare files written under the case dir.
compare_case() {
  local label=$1
  shift
  local ok=1 relative
  for relative in "$@"; do
    if ! diff -u "$WORK/o/case/$relative" "$WORK/r/case/$relative" > /dev/null 2>&1; then
      ok=0
      printf 'FAIL  %s: case/%s differs\n' "$label" "$relative" >&2
      diff -u "$WORK/o/case/$relative" "$WORK/r/case/$relative" >&2 || true
    fi
  done
  if [ "$ok" = 1 ]; then
    pass "$label (artifacts)"
  else
    fail "$label (artifacts)"
  fi
}

require_binaries() {
  local name
  for name in audio-diag jam shabda synth midi-bridge renoise-osc-config sc-live sc-record flacspec mp nb qe; do
    [ -x "$BIN_DIR/$name" ] || {
      echo "parity: binary not executable: $BIN_DIR/$name" >&2
      echo "parity: run cargo build --locked first, or pass --bin-dir DIR" >&2
      exit 2
    }
    recover "$name" || {
      echo "parity: original script not found: $ORIGINALS/$name" >&2
      exit 2
    }
  done
}

# The sh originals source `_localbin.sh` from their own directory.
if [ -r "$ORIGINALS/_localbin.sh" ]; then
  cp -- "$ORIGINALS/_localbin.sh" "$WORK/originals/_localbin.sh"
fi

if [ "$LIST_ONLY" = 1 ]; then
  printf '%s\n' audio-diag jam shabda synth midi-bridge renoise-osc-config sc-live sc-record flacspec mp nb qe
  exit 0
fi

require_binaries

# ---------------------------------------------------------------------------
# audio-diag
# ---------------------------------------------------------------------------
setup_audio_diag_config() {
  local home=$1
  mkdir -p "$home/.config/wireplumber"
  printf 'wireplumber.settings = { restore-target = false }\n' > "$home/.config/wireplumber/main.conf"
}

audio_diag_fakes() {
  local directory=$1
  fake_into "$directory" date 'printf "2026-11-03 12:00:00\n"'
  fake_into "$directory" pw-link 'case "$1" in
  -l) cat "$FAKE_PWLINK_LIST" ;;
  -o) cat "$FAKE_PWLINK_OUT" ;;
esac'
  fake_into "$directory" wpctl 'case "$1" in
  status) cat "$FAKE_WPCTL_STATUS" ;;
  get-volume) cat "$FAKE_WPCTL_VOLUME" ;;
esac'
  fake_into "$directory" amixer 'cat "$FAKE_AMIXER"'
  fake_into "$directory" pgrep 'exit "${FAKE_PGREP_CODE:-1}"'
  fake_into "$directory" systemctl 'cat "$FAKE_SYSTEMCTL"'
}

AUDIO_DIAG_FAKES=$WORK/audio-diag-fakes
audio_diag_fakes "$AUDIO_DIAG_FAKES"

cat > "$WORK/ad-healthy-links" << 'EOF'
playback.game-stereo:output_FL
  |-> RME:playback_AUX2
playback.game-stereo:output_FR
  |-> RME:playback_AUX3
EOF
cat > "$WORK/ad-healthy-status" << 'EOF'
Audio
 ├─ Sinks:
 │  *   41. game-stereo                                                  [Audio/Sink]
 │      71. RME AIO Pro_24048964 Pro            [vol: 1.00]
 ├─ Filters:
 │      40. playback.game-stereo                                         [Stream/Output/Audio]
EOF
printf 'Volume: 1.00\n' > "$WORK/ad-volume-unity"
printf 'Volume: 0.50 [MUTED]\n' > "$WORK/ad-volume-muted"
{
  for channel in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
    printf "numid=%s,iface=MIXER,name='Chn'\n" "$channel"
    printf '  ; type=INTEGER,access=rw------,values=1,min=0,max=65536,step=1\n'
    printf '  : values=64\n'
  done
} > "$WORK/ad-amixer-unity"
{
  for channel in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
    printf "numid=%s,iface=MIXER,name='Chn'\n" "$channel"
    printf '  ; type=INTEGER,access=rw------,values=1,min=0,max=65536,step=1\n'
    if [ "$channel" = 4 ]; then
      printf '  : values=32\n'
    else
      printf '  : values=64\n'
    fi
  done
} > "$WORK/ad-amixer-bad"
printf 'PULSE_SINK=game-stereo\n' > "$WORK/ad-systemctl-mpd"

if selected audio-diag; then
  section "audio-diag"

  AD_ENV=(
    "FAKE_PWLINK_LIST=$WORK/ad-healthy-links"
    "FAKE_PWLINK_OUT="
    "FAKE_WPCTL_STATUS=$WORK/ad-healthy-status"
    "FAKE_WPCTL_VOLUME=$WORK/ad-volume-unity"
    "FAKE_AMIXER=$WORK/ad-amixer-unity"
    "FAKE_PGREP_CODE=1"
    "FAKE_SYSTEMCTL=$WORK/ad-systemctl-mpd"
  )

  SETUP=setup_audio_diag_config
  compare "audio-diag: healthy chain" "$BASH_BIN" audio-diag "$AUDIO_DIAG_FAKES" "${AD_ENV[@]}" -- || true

  cat > "$WORK/ad-bad-links" << 'EOF'
playback.game-stereo:output_FL
  |-> RME:playback_AUX2
multimedia:output_FL
  |-> RME:playback_AUX2
firefox:output_FL
  |-> RME:playback_AUX0
EOF
  SETUP=
  compare "audio-diag: bad routing and volumes" "$BASH_BIN" audio-diag "$AUDIO_DIAG_FAKES" \
    "FAKE_PWLINK_LIST=$WORK/ad-bad-links" \
    "FAKE_PWLINK_OUT=" \
    "FAKE_WPCTL_STATUS=$WORK/ad-healthy-status" \
    "FAKE_WPCTL_VOLUME=$WORK/ad-volume-muted" \
    "FAKE_AMIXER=$WORK/ad-amixer-bad" \
    "FAKE_PGREP_CODE=0" \
    "FAKE_SYSTEMCTL=/dev/null" -- || true

  # restore-target found through the third (XDG_DATA_DIRS) operand.
  mkdir -p "$WORK/xdg/wireplumber"
  printf 'restore-target=false\n' > "$WORK/xdg/wireplumber/50-default.conf"
  SETUP=
  compare "audio-diag: XDG_DATA_DIRS search" "$BASH_BIN" audio-diag "$AUDIO_DIAG_FAKES" \
    "${AD_ENV[@]}" "XDG_DATA_DIRS=$WORK/xdg" -- || true

  # None of the three essential tools: warnings, FAILs, exit 2.
  mkdir -p "$WORK/ad-minimal"
  cp -- "$AUDIO_DIAG_FAKES/date" "$WORK/ad-minimal/date"
  compare "audio-diag: missing essential tools" "$BASH_BIN" audio-diag "$WORK/ad-minimal" \
    "FAKE_WPCTL_VOLUME=$WORK/ad-volume-unity" -- || true
fi

# ---------------------------------------------------------------------------
# jam
# ---------------------------------------------------------------------------
JAM_FAKES=$WORK/jam-fakes
fake_into "$JAM_FAKES" pw-link 'case "$1" in
  -o) if [ -f "$HOME/sc.state" ]; then printf "SuperCollider:out_1\nSuperCollider:out_2\n"; fi ;;
esac'
fake_into "$JAM_FAKES" acn 'true'
fake_into "$JAM_FAKES" aconnect 'cat "$FAKE_ACONNECT"'
fake_into "$JAM_FAKES" pgrep 'if [ -f "$HOME/vital.state" ]; then exit 0; fi; exit 1'
fake_into "$JAM_FAKES" systemctl 'case "$*" in
  *"start vital-standalone"*) : > "$HOME/vital.state" ;;
  *"stop vital-standalone"*) rm -f "$HOME/vital.state" ;;
esac'
fake_into "$JAM_FAKES" sleep 'exit 0'

setup_jam() {
  local home=$1
  mkdir -p "$home/.local/bin"
  {
    log_prelude sc-live
    printf ': > "$HOME/sc.state"\n'
  } > "$home/.local/bin/sc-live"
  chmod +x "$home/.local/bin/sc-live"
  {
    log_prelude midi-bridge
    printf 'exit "${FAKE_BRIDGE_CODE:-0}"\n'
  } > "$home/.local/bin/midi-bridge"
  chmod +x "$home/.local/bin/midi-bridge"
}

setup_jam_up() {
  setup_jam "$1"
  : > "$1/vital.state"
  : > "$1/sc.state"
}

printf 'client 14: '\''Midi Through'\'' [type=kernel]\n    0 '\''Midi Through Port-0'\''\n\tConnecting To: 14:0\n' > "$WORK/jam-aconnect"

if selected jam; then
  section "jam"

  SETUP=setup_jam
  SORT_LOG=1
  compare "jam: cold start" "$BASH_BIN" jam "$JAM_FAKES" "FAKE_ACONNECT=$WORK/jam-aconnect" -- start || true
  SORT_LOG=1
  compare "jam: default command is start" "$BASH_BIN" jam "$JAM_FAKES" "FAKE_ACONNECT=$WORK/jam-aconnect" -- || true

  SETUP=setup_jam_up
  compare "jam: everything already up" "$BASH_BIN" jam "$JAM_FAKES" "FAKE_ACONNECT=$WORK/jam-aconnect" -- start || true

  setup_jam_bridge_fail() {
    setup_jam "$1"
    printf 'exit 1\n' >> "$1/.local/bin/midi-bridge"
  }
  SETUP=setup_jam_bridge_fail
  SORT_LOG=1
  compare "jam: bridge failure warning" "$BASH_BIN" jam "$JAM_FAKES" "FAKE_ACONNECT=$WORK/jam-aconnect" -- start || true

  SETUP=setup_jam_up
  compare "jam: status connected" "$BASH_BIN" jam "$JAM_FAKES" "FAKE_ACONNECT=$WORK/jam-aconnect" -- status || true

  SETUP=setup_jam
  compare "jam: status idle" "$BASH_BIN" jam "$JAM_FAKES" "FAKE_ACONNECT=$WORK/jam-aconnect" -- status || true

  SETUP=setup_jam_up
  compare "jam: stop" "$BASH_BIN" jam "$JAM_FAKES" "FAKE_ACONNECT=$WORK/jam-aconnect" -- stop || true

  SETUP=setup_jam_up
  compare "jam: unknown command" "$BASH_BIN" jam "$JAM_FAKES" -- frobnicate || true
  compare "jam: empty command starts" "$BASH_BIN" jam "$JAM_FAKES" "FAKE_ACONNECT=$WORK/jam-aconnect" -- "" || true

  # The scene helper is missing: the background spawn diagnostic is visible.
  setup_jam_no_scene() {
    setup_jam "$1"
    rm -f "$1/.local/bin/sc-live"
  }
  SETUP=setup_jam_no_scene
  compare "jam: missing sc-live helper" "$BASH_BIN" jam "$JAM_FAKES" "FAKE_ACONNECT=$WORK/jam-aconnect" -- start || true

  # `sleep` is not in PATH: `set -e` stops the start flow after sc-live.
  mkdir -p "$WORK/jam-nosleep"
  cp -- "$JAM_FAKES/pw-link" "$JAM_FAKES/aconnect" "$JAM_FAKES/pgrep" "$JAM_FAKES/systemctl" "$WORK/jam-nosleep/"
  SETUP=setup_jam
  compare "jam: missing sleep" "$BASH_BIN" jam "$WORK/jam-nosleep" "FAKE_ACONNECT=$WORK/jam-aconnect" -- start || true
fi

# ---------------------------------------------------------------------------
# shabda
# ---------------------------------------------------------------------------
SHABDA_FAKES=$WORK/shabda-fakes
fake_into "$SHABDA_FAKES" vivaldi 'exit 0'
fake_into "$SHABDA_FAKES" wl-copy 'cat > "$HOME/clip"'

setup_shabda_existing() {
  local home=$1
  mkdir -p "$home/notes/music/tidal"
  printf '!reslist "https://shabda.ndre.gr/amen.json?licenses=by,cc0,by-nc"\n' \
    > "$home/notes/music/tidal/shabda-samples.json"
}

setup_shabda_other() {
  local home=$1
  mkdir -p "$home/notes/music/tidal"
  printf '!reslist "https://shabda.ndre.gr/techno.json?licenses=by,cc0,by-nc"\n' \
    > "$home/notes/music/tidal/shabda-samples.json"
}

if selected shabda; then
  section "shabda"

  SETUP=
  compare "shabda: no pack opens the browser" "$BASH_BIN" shabda "$SHABDA_FAKES" -- || true

  compare "shabda: list Tidal line" "$BASH_BIN" shabda "$SHABDA_FAKES" -- -l amen || true
  compare "shabda: list Strudel line" "$BASH_BIN" shabda "$SHABDA_FAKES" -- -s -l 808 || true
  compare "shabda: combined short options" "$BASH_BIN" shabda "$SHABDA_FAKES" -- -sl "amen breaks" || true
  compare "shabda: option-like pack after --" "$BASH_BIN" shabda "$SHABDA_FAKES" -- -- -x || true
  compare "shabda: options stop at the first operand" "$BASH_BIN" shabda "$SHABDA_FAKES" -- amen -s || true
  compare "shabda: lone - is an operand" "$BASH_BIN" shabda "$SHABDA_FAKES" -- - || true
  compare "shabda: -s without pack opens the browser" "$BASH_BIN" shabda "$SHABDA_FAKES" -- -s || true

  SETUP=
  compare "shabda: copy Tidal line to the clipboard" "$BASH_BIN" shabda "$SHABDA_FAKES" -- 808 || true
  compare_home "shabda: clipboard payload (Tidal)" clip
  SETUP=
  compare "shabda: copy Strudel line to the clipboard" "$BASH_BIN" shabda "$SHABDA_FAKES" -- -s amen || true

  SETUP=
  compare "shabda: append creates the list" "$BASH_BIN" shabda "$SHABDA_FAKES" -- -a amen || true
  compare_home "shabda: appended list" notes/music/tidal/shabda-samples.json

  SETUP=setup_shabda_existing
  compare "shabda: append skips an existing pack" "$BASH_BIN" shabda "$SHABDA_FAKES" -- -a amen || true
  compare_home "shabda: unchanged list" notes/music/tidal/shabda-samples.json

  SETUP=setup_shabda_other
  compare "shabda: append adds another pack" "$BASH_BIN" shabda "$SHABDA_FAKES" -- -a amen || true
  compare_home "shabda: extended list" notes/music/tidal/shabda-samples.json

  SETUP=setup_shabda_existing
  compare "shabda: append wins over list-only" "$BASH_BIN" shabda "$SHABDA_FAKES" -- -a -l amen || true

  SETUP=
  compare "shabda: illegal option" "$BASH_BIN" shabda "$SHABDA_FAKES" -- -x pack || true
  compare "shabda: -h is an illegal option" "$BASH_BIN" shabda "$SHABDA_FAKES" -- -h || true

  # No wl-copy in PATH: the line is printed instead.
  mkdir -p "$WORK/shabda-nowl"
  cp -- "$SHABDA_FAKES/vivaldi" "$WORK/shabda-nowl/"
  SETUP=
  compare "shabda: no wl-copy" "$BASH_BIN" shabda "$WORK/shabda-nowl" -- amen || true

  # No browser in PATH: the spawn failure is silent.
  mkdir -p "$WORK/shabda-novivaldi"
  cp -- "$SHABDA_FAKES/wl-copy" "$WORK/shabda-novivaldi/"
  SETUP=
  compare "shabda: no browser" "$BASH_BIN" shabda "$WORK/shabda-novivaldi" -- amen || true

  # wl-copy fails: `set -e` ends the script before the final messages.
  fake_into "$WORK/shabda-copyfail" wl-copy 'exit 3'
  fake_into "$WORK/shabda-copyfail" vivaldi 'exit 0'
  SETUP=
  compare "shabda: clipboard failure" "$BASH_BIN" shabda "$WORK/shabda-copyfail" -- amen || true
fi

# ---------------------------------------------------------------------------
# synth
# ---------------------------------------------------------------------------
SYNTH_FAKES=$WORK/synth-fakes
fake_into "$SYNTH_FAKES" pgrep 'exit "${FAKE_PGREP_CODE:-1}"'
fake_into "$SYNTH_FAKES" systemctl 'exit "${FAKE_SYSTEMCTL_CODE:-0}"'
fake_into "$SYNTH_FAKES" nohup 'exit 0'
fake_into "$SYNTH_FAKES" hyprctl 'case "$1" in
  clients) cat "$FAKE_HYPR_JSON" ;;
  dispatch) exit "${FAKE_HYPR_DISPATCH_CODE:-0}" ;;
esac'

cat > "$WORK/synth-windows.json" << 'EOF'
[{"address":"0xaaa","class":"Surge XT","title":"Surge XT - patch"},
 {"address":"0xbbb","class":"Renoise","title":"Renoise 3.5.4"}]
EOF
cat > "$WORK/synth-empty.json" << 'EOF'
[{"address":"0xccc","class":"Firefox","title":"Mozilla Firefox"}]
EOF

if selected synth; then
  section "synth"

  SETUP=
  compare "synth: Surge XT raised" "$BASH_BIN" synth "$SYNTH_FAKES" \
    "FAKE_PGREP_CODE=0" "FAKE_HYPR_JSON=$WORK/synth-windows.json" -- Surge_XT || true
  compare "synth: Surge XT already running (no window)" "$BASH_BIN" synth "$SYNTH_FAKES" \
    "FAKE_PGREP_CODE=0" "FAKE_HYPR_JSON=$WORK/synth-empty.json" -- Surge_XT || true
  compare "synth: Surge XT starts" "$BASH_BIN" synth "$SYNTH_FAKES" \
    "FAKE_PGREP_CODE=1" -- Surge_XT || true
  compare "synth: surge alias" "$BASH_BIN" synth "$SYNTH_FAKES" \
    "FAKE_PGREP_CODE=1" -- surge || true
  compare "synth: Surge candidate alias" "$BASH_BIN" synth "$SYNTH_FAKES" \
    "FAKE_PGREP_CODE=1" -- SurgeXT || true

  compare "synth: Vital already running" "$BASH_BIN" synth "$SYNTH_FAKES" \
    "FAKE_PGREP_CODE=0" -- Vital || true
  compare "synth: Vital starts" "$BASH_BIN" synth "$SYNTH_FAKES" \
    "FAKE_PGREP_CODE=1" -- Vital || true
  compare "synth: Vital service failure" "$BASH_BIN" synth "$SYNTH_FAKES" \
    "FAKE_PGREP_CODE=1" "FAKE_SYSTEMCTL_CODE=5" -- Vital || true

  compare "synth: Renoise raised for a VST" "$BASH_BIN" synth "$SYNTH_FAKES" \
    "FAKE_PGREP_CODE=0" "FAKE_HYPR_JSON=$WORK/synth-windows.json" -- LegendHZ || true
  compare "synth: Renoise starts for a VST" "$BASH_BIN" synth "$SYNTH_FAKES" \
    "FAKE_PGREP_CODE=1" -- LegendHZ || true
  compare "synth: vst3 prefix and spaces" "$BASH_BIN" synth "$SYNTH_FAKES" \
    "FAKE_PGREP_CODE=1" -- "vst3:Legend  HZ" || true

  compare "synth: missing name" "$BASH_BIN" synth "$SYNTH_FAKES" -- || true
  compare "synth: empty name" "$BASH_BIN" synth "$SYNTH_FAKES" -- "" || true

  # No hyprctl: the window cannot be raised, the already-running message wins.
  mkdir -p "$WORK/synth-nohyprctl"
  cp -- "$SYNTH_FAKES/pgrep" "$SYNTH_FAKES/systemctl" "$SYNTH_FAKES/nohup" "$WORK/synth-nohyprctl/"
  compare "synth: no hyprctl" "$BASH_BIN" synth "$WORK/synth-nohyprctl" \
    "FAKE_PGREP_CODE=0" -- Surge_XT || true
fi

# ---------------------------------------------------------------------------
# midi-bridge
# ---------------------------------------------------------------------------
MIDI_FAKES=$WORK/midi-fakes
fake_into "$MIDI_FAKES" aconnect 'case "$1" in
  -l) exit "${FAKE_ACONNECT_LIST_CODE:-0}"; cat "$FAKE_ACONNECT_LIST" ;;
  *)
    if [ "${FAKE_ACONNECT_FAIL:-0}" = 1 ]; then
      printf "connect failed: %s\n" "$2" >&2
      exit 1
    fi
    ;;
esac'

cat > "$WORK/midi-full.list" << 'EOF'
client 0: 'System' [type=kernel]
    0 'Timer           '
client 14: 'Midi Through' [type=kernel]
    0 'Midi Through Port-0'
client 128: 'SuperCollider' [type=user,pid=100]
    0 'SuperCollider MIDI In'
    1 'out0'
client 129: 'Renoise' [type=user,pid=200]
    0 'midi in'
EOF
cat > "$WORK/midi-no-renoise.list" << 'EOF'
client 14: 'Midi Through' [type=kernel]
    0 'Midi Through Port-0'
client 128: 'SuperCollider' [type=user,pid=100]
    1 'out0'
EOF
cat > "$WORK/midi-no-out.list" << 'EOF'
client 14: 'Midi Through' [type=kernel]
    0 'Midi Through Port-0'
client 128: 'SuperCollider' [type=user,pid=100]
    0 'SuperCollider MIDI In'
EOF
cat > "$WORK/midi-no-sc.list" << 'EOF'
client 14: 'Midi Through' [type=kernel]
    0 'Midi Through Port-0'
client 129: 'Renoise' [type=user,pid=200]
    0 'midi in'
EOF

if selected midi-bridge; then
  section "midi-bridge"

  SETUP=
  compare "midi-bridge: Renoise and Midi Through" "$BASH_BIN" midi-bridge "$MIDI_FAKES" \
    "FAKE_ACONNECT_LIST=$WORK/midi-full.list" -- || true
  compare "midi-bridge: no Renoise" "$BASH_BIN" midi-bridge "$MIDI_FAKES" \
    "FAKE_ACONNECT_LIST=$WORK/midi-no-renoise.list" -- || true
  compare "midi-bridge: no SC out0 port" "$BASH_BIN" midi-bridge "$MIDI_FAKES" \
    "FAKE_ACONNECT_LIST=$WORK/midi-no-out.list" -- || true
  compare "midi-bridge: no SuperCollider client" "$BASH_BIN" midi-bridge "$MIDI_FAKES" \
    "FAKE_ACONNECT_LIST=$WORK/midi-no-sc.list" -- || true
  compare "midi-bridge: failed connection" "$BASH_BIN" midi-bridge "$MIDI_FAKES" \
    "FAKE_ACONNECT_LIST=$WORK/midi-full.list" "FAKE_ACONNECT_FAIL=1" -- || true
  compare "midi-bridge: listing failure" "$BASH_BIN" midi-bridge "$MIDI_FAKES" \
    "FAKE_ACONNECT_LIST=$WORK/midi-full.list" "FAKE_ACONNECT_LIST_CODE=4" -- || true

  # No aconnect at all: the first listing aborts with bash's 127.
  mkdir -p "$WORK/midi-none"
  compare "midi-bridge: missing aconnect" "$BASH_BIN" midi-bridge "$WORK/midi-none" -- || true
fi

# ---------------------------------------------------------------------------
# renoise-osc-config
# ---------------------------------------------------------------------------
RENOISE_FAKES=$WORK/renoise-fakes
fake_into "$RENOISE_FAKES" pgrep 'exit "${FAKE_PGREP_CODE:-1}"'

renoise_config() {
  local home=$1 body=$2
  mkdir -p "$home/.config/Renoise/V3.5.4"
  printf '%s' "$body" > "$home/.config/Renoise/V3.5.4/Config.xml"
}

setup_renoise_disabled() {
  renoise_config "$1" '<?xml version="1.0" encoding="UTF-8"?>
<RenoiseConfig>
  <OscServerEnabled>false</OscServerEnabled>
  <OscServerProtocol>Tcp</OscServerProtocol>
  <OscServerPort>9000</OscServerPort>
</RenoiseConfig>
'
}

setup_renoise_enabled() {
  renoise_config "$1" '<?xml version="1.0" encoding="UTF-8"?>
<RenoiseConfig>
  <OscServerEnabled>true</OscServerEnabled>
  <OscServerProtocol>Udp</OscServerProtocol>
  <OscServerPort>9001</OscServerPort>
</RenoiseConfig>
'
}

setup_renoise_crlf() {
  local home=$1
  mkdir -p "$home/.config/Renoise/V3.5.4"
  printf '<RenoiseConfig>\r\n<OscServerEnabled>false</OscServerEnabled>\r\n<OscServerProtocol>Tcp</OscServerProtocol>\r\n<OscServerPort>9000</OscServerPort>\r\n</RenoiseConfig>\r\n' \
    > "$home/.config/Renoise/V3.5.4/Config.xml"
}

setup_renoise_untagged() {
  renoise_config "$1" '<RenoiseConfig>
  <SomeOther>1</SomeOther>
</RenoiseConfig>
'
}

setup_renoise_split_tags() {
  renoise_config "$1" '<RenoiseConfig>
<OscServerEnabled>
</OscServerEnabled>
<OscServerPort>9000</OscServerPort>
</RenoiseConfig>
'
}

setup_renoise_backup_exists() {
  setup_renoise_disabled "$1"
  printf 'old backup\n' > "$1/.config/Renoise/V3.5.4/Config.xml.renoise-osc.bak"
}

setup_renoise_missing() {
  local home=$1
  mkdir -p "$home"
  : "$home"
}

RENOISE_FILE=.config/Renoise/V3.5.4/Config.xml
RENOISE_BACKUP=.config/Renoise/V3.5.4/Config.xml.renoise-osc.bak

if selected renoise-osc-config; then
  section "renoise-osc-config"

  SETUP=setup_renoise_disabled
  compare "renoise-osc-config: disabled tags are enabled" "$BASH_BIN" renoise-osc-config "$RENOISE_FAKES" -- || true
  compare_home "renoise-osc-config: rewritten disabled config" "$RENOISE_FILE" "$RENOISE_BACKUP"

  SETUP=setup_renoise_enabled
  compare "renoise-osc-config: port is pinned" "$BASH_BIN" renoise-osc-config "$RENOISE_FAKES" -- || true
  compare_home "renoise-osc-config: pinned config" "$RENOISE_FILE" "$RENOISE_BACKUP"

  SETUP=setup_renoise_enabled
  compare "renoise-osc-config: RENOISE_OSC_PORT override" "$BASH_BIN" renoise-osc-config "$RENOISE_FAKES" \
    "RENOISE_OSC_PORT=9123" -- || true
  compare_home "renoise-osc-config: override config" "$RENOISE_FILE" "$RENOISE_BACKUP"

  SETUP=setup_renoise_enabled
  compare "renoise-osc-config: empty port falls back" "$BASH_BIN" renoise-osc-config "$RENOISE_FAKES" \
    "RENOISE_OSC_PORT=" -- || true

  SETUP=setup_renoise_enabled
  compare "renoise-osc-config: renoise is running" "$BASH_BIN" renoise-osc-config "$RENOISE_FAKES" \
    "FAKE_PGREP_CODE=0" -- || true
  compare_home "renoise-osc-config: untouched config" "$RENOISE_FILE"

  SETUP=setup_renoise_missing
  compare "renoise-osc-config: missing config" "$BASH_BIN" renoise-osc-config "$RENOISE_FAKES" -- || true

  SETUP=setup_renoise_crlf
  compare "renoise-osc-config: CRLF file" "$BASH_BIN" renoise-osc-config "$RENOISE_FAKES" -- || true
  compare_home "renoise-osc-config: newline-normalised config" "$RENOISE_FILE" "$RENOISE_BACKUP"

  SETUP=setup_renoise_untagged
  compare "renoise-osc-config: no OSC tags" "$BASH_BIN" renoise-osc-config "$RENOISE_FAKES" -- || true
  compare_home "renoise-osc-config: unchanged untagged config" "$RENOISE_FILE" "$RENOISE_BACKUP"

  SETUP=setup_renoise_split_tags
  compare "renoise-osc-config: tags split across lines" "$BASH_BIN" renoise-osc-config "$RENOISE_FAKES" -- || true
  compare_home "renoise-osc-config: split-tag config" "$RENOISE_FILE" "$RENOISE_BACKUP"

  setup_renoise_second_tag() {
    renoise_config "$1" '<RenoiseConfig>
<OscServerEnabled>
</OscServerEnabled>
<OscServerEnabled>false</OscServerEnabled>
</RenoiseConfig>
'
  }
  SETUP=setup_renoise_second_tag
  compare "renoise-osc-config: later same-line tag" "$BASH_BIN" renoise-osc-config "$RENOISE_FAKES" -- || true
  compare_home "renoise-osc-config: later-tag config" "$RENOISE_FILE" "$RENOISE_BACKUP"

  SETUP=setup_renoise_backup_exists
  compare "renoise-osc-config: backup is kept" "$BASH_BIN" renoise-osc-config "$RENOISE_FAKES" -- || true
  compare_home "renoise-osc-config: existing backup" "$RENOISE_FILE" "$RENOISE_BACKUP"

  # No pgrep in PATH: the probe is silent and the rewrite still happens.
  mkdir -p "$WORK/renoise-nopgrep"
  SETUP=setup_renoise_disabled
  compare "renoise-osc-config: no pgrep" "$BASH_BIN" renoise-osc-config "$WORK/renoise-nopgrep" -- || true
fi

# ---------------------------------------------------------------------------
# sc-live
# ---------------------------------------------------------------------------
SCLIVE_FAKES=$WORK/sclive-fakes
fake_into "$SCLIVE_FAKES" pgrep 'exit "${FAKE_PGREP_CODE:-1}"'
fake_into "$SCLIVE_FAKES" pw-link 'cat "$FAKE_PWLINK_OUT"'
printf 'SuperCollider:out_1\nSuperCollider:out_2\n' > "$WORK/sclive-linked"

setup_scene() {
  local home=$1
  mkdir -p "$home/notes/music/supercollider" "$home/.local/bin"
  printf '// live.scd\n' > "$home/notes/music/supercollider/live.scd"
  {
    log_prelude v
    printf 'printf "v-stdout\\n"\n'
    printf 'exit "${FAKE_V_CODE:-0}"\n'
  } > "$home/.local/bin/v"
  chmod +x "$home/.local/bin/v"
}

setup_scene_nov() {
  setup_scene "$1"
  rm -f "$1/.local/bin/v"
}

setup_scene_nonexec() {
  setup_scene "$1"
  chmod -x "$1/.local/bin/v"
}

if selected sc-live; then
  section "sc-live"

  SETUP=setup_scene
  compare "sc-live: status running" "$BASH_BIN" sc-live "$SCLIVE_FAKES" \
    "FAKE_PGREP_CODE=0" "FAKE_PWLINK_OUT=$WORK/sclive-linked" -- status || true
  compare "sc-live: status idle" "$BASH_BIN" sc-live "$SCLIVE_FAKES" \
    "FAKE_PGREP_CODE=1" "FAKE_PWLINK_OUT=/dev/null" -- status || true
  compare "sc-live: status ignores extra arguments" "$BASH_BIN" sc-live "$SCLIVE_FAKES" \
    "FAKE_PGREP_CODE=0" "FAKE_PWLINK_OUT=$WORK/sclive-linked" -- status extra || true

  compare "sc-live: opens the default scene" "$BASH_BIN" sc-live "$SCLIVE_FAKES" -- || true
  compare "sc-live: opens an argument scene" "$BASH_BIN" sc-live "$SCLIVE_FAKES" -- other.scd || true
  compare "sc-live: empty argument means the default scene" "$BASH_BIN" sc-live "$SCLIVE_FAKES" -- "" || true
  compare "sc-live: editor exit status" "$BASH_BIN" sc-live "$SCLIVE_FAKES" "FAKE_V_CODE=7" -- || true

  setup_scene_missing() {
    local home=$1
    mkdir -p "$home/.local/bin"
    cp -- "$WORK/o/home/.local/bin/v" "$home/.local/bin/v" 2> /dev/null || true
    : "$home"
  }
  SETUP=setup_scene_missing
  compare "sc-live: missing scene" "$BASH_BIN" sc-live "$SCLIVE_FAKES" -- || true

  SETUP=setup_scene_nonexec
  compare "sc-live: editor not executable" "$BASH_BIN" sc-live "$SCLIVE_FAKES" -- || true

  SETUP=setup_scene_nov
  compare "sc-live: editor missing" "$BASH_BIN" sc-live "$SCLIVE_FAKES" -- || true

  # pgrep and pw-link are not in PATH: the status probes degrade to "not running".
  SETUP=setup_scene
  compare "sc-live: status without probes" "$BASH_BIN" sc-live "$WORK/midi-none" -- status || true
fi

# ---------------------------------------------------------------------------
# sc-record
# ---------------------------------------------------------------------------
SCRECORD_FAKES=$WORK/screcord-fakes
fake_into "$SCRECORD_FAKES" pw-link 'cat "$FAKE_PWLINK_OUT"; exit "${FAKE_PWLINK_CODE:-0}"'
fake_into "$SCRECORD_FAKES" timeout 'exit "${FAKE_TIMEOUT_CODE:-0}"'
fake_into "$SCRECORD_FAKES" pw-record 'exit 0'

if selected sc-record; then
  section "sc-record"

  SETUP=
  compare "sc-record: default duration" "$BASH_BIN" sc-record "$SCRECORD_FAKES" \
    "FAKE_PWLINK_OUT=$WORK/sclive-linked" -- out.wav || true
  compare "sc-record: custom duration" "$BASH_BIN" sc-record "$SCRECORD_FAKES" \
    "FAKE_PWLINK_OUT=$WORK/sclive-linked" -- out.wav 12 || true
  compare "sc-record: empty duration uses the default" "$BASH_BIN" sc-record "$SCRECORD_FAKES" \
    "FAKE_PWLINK_OUT=$WORK/sclive-linked" -- out.wav "" || true
  compare "sc-record: no engine link" "$BASH_BIN" sc-record "$SCRECORD_FAKES" \
    "FAKE_PWLINK_OUT=/dev/null" -- out.wav || true
  compare "sc-record: pw-link failure" "$BASH_BIN" sc-record "$SCRECORD_FAKES" \
    "FAKE_PWLINK_OUT=$WORK/sclive-linked" "FAKE_PWLINK_CODE=3" -- out.wav || true
  compare "sc-record: timeout status stops the script" "$BASH_BIN" sc-record "$SCRECORD_FAKES" \
    "FAKE_PWLINK_OUT=$WORK/sclive-linked" "FAKE_TIMEOUT_CODE=124" -- out.wav 5 || true
  compare "sc-record: missing output argument" "$BASH_BIN" sc-record "$SCRECORD_FAKES" -- || true
  compare "sc-record: empty output argument" "$BASH_BIN" sc-record "$SCRECORD_FAKES" -- "" || true

  # A timeout helper killed by SIGINT: both sides exit 130 with no extra
  # output. (SIGTERM makes bash print its foreground job notification, which a
  # port cannot reproduce; the exit status is covered by the Rust tests.)
  fake_into "$WORK/screcord-signalled" pw-link 'cat "$FAKE_PWLINK_OUT"'
  fake_into "$WORK/screcord-signalled" timeout 'kill -INT $$'
  compare "sc-record: signalled timeout" "$BASH_BIN" sc-record "$WORK/screcord-signalled" \
    "FAKE_PWLINK_OUT=$WORK/sclive-linked" -- out.wav || true

  # No timeout in PATH: `set -e` aborts with bash's command-not-found.
  mkdir -p "$WORK/screcord-notimeout"
  cp -- "$SCRECORD_FAKES/pw-link" "$WORK/screcord-notimeout/"
  compare "sc-record: missing timeout" "$BASH_BIN" sc-record "$WORK/screcord-notimeout" \
    "FAKE_PWLINK_OUT=$WORK/sclive-linked" -- out.wav || true

  # No pw-link: the probe fails, the script reports the missing engine.
  mkdir -p "$WORK/screcord-nolink"
  cp -- "$SCRECORD_FAKES/timeout" "$WORK/screcord-nolink/"
  compare "sc-record: missing pw-link" "$BASH_BIN" sc-record "$WORK/screcord-nolink" -- out.wav || true
fi

# ---------------------------------------------------------------------------
# flacspec
# ---------------------------------------------------------------------------
FLACSPEC_FAKES=$WORK/flacspec-fakes
fake_into "$FLACSPEC_FAKES" sox 'out=
previous=
for arg in "$@"; do
  if [ "$previous" = "-o" ]; then out=$arg; fi
  previous=$arg
done
printf "SOX:%s\n" "$1" > "$out"
case "$1" in
  *fail*) exit 7 ;;
esac'

setup_flac_none() {
  local case_dir=$2
  mkdir -p "$case_dir"
}

setup_flac_one() {
  local case_dir=$2
  mkdir -p "$case_dir"
  printf 'fLaC one\n' > "$case_dir/one.flac"
}

setup_flac_many() {
  local case_dir=$2
  mkdir -p "$case_dir/dir.flac"
  printf 'fLaC a\n' > "$case_dir/a.flac"
  printf 'fLaC b\n' > "$case_dir/a.b.flac"
  printf 'fLaC hidden\n' > "$case_dir/.hidden.flac"
  printf 'fLaC dir-entry\n' > "$case_dir/dir.flac/inner.flac"
  printf 'not audio\n' > "$case_dir/target.dat"
  ln -sf target.dat "$case_dir/link.flac"
}

setup_flac_fail() {
  local case_dir=$2
  mkdir -p "$case_dir"
  printf 'fLaC ok\n' > "$case_dir/ok.flac"
  printf 'fLaC broken\n' > "$case_dir/fail.flac"
}

setup_flac_blocked() {
  local case_dir=$2
  mkdir -p "$case_dir"
  printf 'fLaC one\n' > "$case_dir/one.flac"
  printf 'not a directory\n' > "$case_dir/Spectrograms"
}

if selected flacspec; then
  section "flacspec"

  SETUP=setup_flac_none
  compare "flacspec: no flac files" "$BASH_BIN" flacspec "$FLACSPEC_FAKES" -- || true
  compare "flacspec: -h prints the header" "$BASH_BIN" flacspec "$FLACSPEC_FAKES" -- -h || true
  compare "flacspec: --help prints the header" "$BASH_BIN" flacspec "$FLACSPEC_FAKES" -- --help || true
  compare "flacspec: other arguments are ignored" "$BASH_BIN" flacspec "$FLACSPEC_FAKES" -- file.txt || true

  SETUP=setup_flac_one
  compare "flacspec: one file" "$BASH_BIN" flacspec "$FLACSPEC_FAKES" -- || true
  compare_case "flacspec: one spectrogram" "Spectrograms/one.flac.png"

  SETUP=setup_flac_many
  compare "flacspec: many files" "$BASH_BIN" flacspec "$FLACSPEC_FAKES" -- || true
  compare_case "flacspec: many spectrograms" \
    "Spectrograms/a.flac.png" "Spectrograms/a.b.flac.png" "Spectrograms/link.flac.png"

  SETUP=setup_flac_fail
  compare "flacspec: failing sox" "$BASH_BIN" flacspec "$FLACSPEC_FAKES" -- || true
  compare_case "flacspec: partial spectrograms" "Spectrograms/ok.flac.png"

  SETUP=setup_flac_blocked
  compare "flacspec: Spectrograms is a file" "$BASH_BIN" flacspec "$FLACSPEC_FAKES" -- || true

  # sox is missing: `need` warns, each spawn reports bash's 127.
  SETUP=setup_flac_one
  mkdir -p "$WORK/flacspec-nosox"
  compare "flacspec: missing sox" "$BASH_BIN" flacspec "$WORK/flacspec-nosox" -- || true
fi

# ---------------------------------------------------------------------------
# mp
# ---------------------------------------------------------------------------
MP_FAKES=$WORK/mp-fakes
fake_into "$MP_FAKES" mpv 'printf "mpv-out\n"
printf "mpv-err\n" >&2
exit "${FAKE_MPV_CODE:-0}"'
# The fake sorts its own argv before logging: `find` emits the directory
# entries in readdir order, which legitimately differs between the two recreated
# fixture trees. The final printf is one write, so concurrent pipelines cannot
# interleave a record.
cat > "$MP_FAKES/vid-info" << 'MPVID'
#!/bin/sh
line="vid-info"
sorted=$(for arg in "$@"; do printf '%s\n' "$arg"; done | LC_ALL=C sort)
while IFS= read -r arg; do
  line="$line$(printf '\t%s' "$arg")"
done <<SORTED
$sorted
SORTED
printf '%s\n' "$line" >> "$FAKE_ARGV_LOG"
exit 0
MPVID
chmod +x "$MP_FAKES/vid-info"

setup_mp_files() {
  local home=$1 case_dir=$2
  mkdir -p "$home/.local/bin"
  cp -- "$MP_FAKES/vid-info" "$home/.local/bin/vid-info"
  chmod +x "$home/.local/bin/vid-info"
  mkdir -p "$case_dir"
  printf 'a' > "$case_dir/a.mp3"
  printf 'b' > "$case_dir/b.flac"
  printf 'c' > "$case_dir/notes.txt"
}

setup_mp_dirs() {
  local home=$1 case_dir=$2
  mkdir -p "$home/.local/bin"
  cp -- "$MP_FAKES/vid-info" "$home/.local/bin/vid-info"
  chmod +x "$home/.local/bin/vid-info"
  mkdir -p "$case_dir/media dir/sub"
  printf 'c' > "$case_dir/media dir/c.wav"
  printf 'd' > "$case_dir/media dir/d.txt"
  printf 'e' > "$case_dir/media dir/sub/e.wav"
}

if selected mp; then
  section "mp"

  SETUP=
  compare "mp: help" "$BASH_BIN" mp "$MP_FAKES" -- -h || true
  compare "mp: --help" "$BASH_BIN" mp "$MP_FAKES" -- --help || true

  SETUP=setup_mp_files
  SORT_LOG=1
  compare "mp: file arguments" "$BASH_BIN" mp "$MP_FAKES" -- a.mp3 b.flac notes.txt || true
  compare_home_norm "mp: mpv log" mp "tmp/mpv.log"

  SETUP=setup_mp_dirs
  SORT_LOG=1
  compare "mp: directory arguments" "$BASH_BIN" mp "$MP_FAKES" -- "media dir" || true
  compare_home_norm "mp: directory mpv log" mp "tmp/mpv.log"

  SETUP=setup_mp_files
  SORT_LOG=1
  compare "mp: mixed files and directories" "$BASH_BIN" mp "$MP_FAKES" -- a.mp3 "." || true

  SETUP=setup_mp_files
  SORT_LOG=1
  compare "mp: no arguments" "$BASH_BIN" mp "$MP_FAKES" -- || true

  SETUP=setup_mp_files
  SORT_LOG=1
  compare "mp: mpv failure status" "$BASH_BIN" mp "$MP_FAKES" "FAKE_MPV_CODE=9" -- a.mp3 || true

  # No mpv: the diagnostic lands in the log file and the status is 127.
  SETUP=setup_mp_files
  mkdir -p "$WORK/mp-nompv"
  cp -- "$MP_FAKES/vid-info" "$WORK/mp-nompv/"
  SORT_LOG=1
  compare "mp: missing mpv" "$BASH_BIN" mp "$WORK/mp-nompv" -- a.mp3 || true
  compare_home_norm "mp: missing-mpv log" mp "tmp/mpv.log"
fi

# ---------------------------------------------------------------------------
# nb
# ---------------------------------------------------------------------------
NB_FAKES=$WORK/nb-fakes
fake_into "$NB_FAKES" git 'case "$*" in
  *" pull"*) exit "${FAKE_GIT_PULL_CODE:-0}" ;;
  *" status --short -b"*) cat "$FAKE_GIT_STATUS"; exit "${FAKE_GIT_STATUS_CODE:-0}" ;;
  *" add ."*) exit 0 ;;
  *" commit "*) exit 0 ;;
  *" push"*) exit "${FAKE_GIT_PUSH_CODE:-0}" ;;
esac
exit 0'
fake_into "$NB_FAKES" date 'printf "01-02-2024 03:04:05\n"'
fake_into "$NB_FAKES" zk 'exit 0'

printf '## main...origin/main\n' > "$WORK/nb-clean.status"
printf '## main...origin/main\n M notes/one.md\n?? notes/two.md\n' > "$WORK/nb-dirty.status"

setup_nb_music() {
  local home=$1
  mkdir -p "$home/music/alpha" "$home/music/beta"
  printf 'x' > "$home/music/file.txt"
  : "$home"
}

setup_nb_nomusic() {
  local home=$1
  mkdir -p "$home"
  : "$home"
}

setup_nb_repo_is_file() {
  local home=$1
  mkdir -p "$home"
  printf 'not a directory\n' > "$home/notes"
}

if selected nb; then
  section "nb"

  SETUP=setup_nb_music
  compare "nb: help" "$BASH_BIN" nb "$NB_FAKES" -- -h || true
  compare "nb: --help" "$BASH_BIN" nb "$NB_FAKES" -- --help || true

  SETUP=setup_nb_music
  compare "nb: no changes" "$BASH_BIN" nb "$NB_FAKES" "FAKE_GIT_STATUS=$WORK/nb-clean.status" -- || true
  compare_home_norm "nb: music list" nb notes/music/list

  SETUP=setup_nb_music
  compare "nb: changes commit and push" "$BASH_BIN" nb "$NB_FAKES" "FAKE_GIT_STATUS=$WORK/nb-dirty.status" -- || true
  compare_home_norm "nb: music list after commit" nb notes/music/list

  SETUP=setup_nb_music
  compare "nb: pull failure is tolerated" "$BASH_BIN" nb "$NB_FAKES" \
    "FAKE_GIT_STATUS=$WORK/nb-dirty.status" "FAKE_GIT_PULL_CODE=3" -- || true

  SETUP=setup_nb_music
  compare "nb: push failure is tolerated" "$BASH_BIN" nb "$NB_FAKES" \
    "FAKE_GIT_STATUS=$WORK/nb-dirty.status" "FAKE_GIT_PUSH_CODE=4" -- || true

  SETUP=setup_nb_music
  compare "nb: status failure counts zero lines" "$BASH_BIN" nb "$NB_FAKES" \
    "FAKE_GIT_STATUS=$WORK/nb-dirty.status" "FAKE_GIT_STATUS_CODE=1" -- || true

  SETUP=setup_nb_nomusic
  compare "nb: missing music directory" "$BASH_BIN" nb "$NB_FAKES" "FAKE_GIT_STATUS=$WORK/nb-clean.status" -- || true
  compare_home "nb: empty music list" notes/music/list

  SETUP=setup_nb_repo_is_file
  compare "nb: notes is a file" "$BASH_BIN" nb "$NB_FAKES" "FAKE_GIT_STATUS=$WORK/nb-clean.status" -- || true

  # git and zk are missing: `need` warns and the status pipeline counts 0.
  SETUP=setup_nb_music
  mkdir -p "$WORK/nb-nogit"
  cp -- "$NB_FAKES/date" "$WORK/nb-nogit/"
  compare "nb: missing git" "$BASH_BIN" nb "$WORK/nb-nogit" -- || true

  # date is missing only on the commit path; git and the line counting remain.
  SETUP=setup_nb_music
  mkdir -p "$WORK/nb-nodate"
  cp -- "$NB_FAKES/git" "$NB_FAKES/zk" "$WORK/nb-nodate/"
  compare "nb: missing date on commit" "$BASH_BIN" nb "$WORK/nb-nodate" \
    "FAKE_GIT_STATUS=$WORK/nb-dirty.status" -- || true

  # zk is absent: the index refresh is skipped, the rest runs.
  SETUP=setup_nb_music
  mkdir -p "$WORK/nb-nozk"
  cp -- "$NB_FAKES/git" "$NB_FAKES/date" "$WORK/nb-nozk/"
  compare "nb: no zk" "$BASH_BIN" nb "$WORK/nb-nozk" "FAKE_GIT_STATUS=$WORK/nb-dirty.status" -- || true
fi

# ---------------------------------------------------------------------------
# qe
# ---------------------------------------------------------------------------
QE_FAKES=$WORK/qe-fakes
mkdir -p "$QE_FAKES"

setup_qe_tree() {
  local case_dir=$2
  mkdir -p "$case_dir/old" "$case_dir/new" "$case_dir/tie_a" "$case_dir/tie_b" \
    "$case_dir/.hidden" "$case_dir/.git" "$case_dir/.gitignore" "$case_dir/real" \
    "$case_dir/real/child"
  printf 'x' > "$case_dir/file.txt"
  ln -s real "$case_dir/link"
  touch -d '2020-01-01 00:00:00' "$case_dir/old" "$case_dir/real"
  touch -d '2021-01-01 00:00:00' "$case_dir/new"
  touch -d '2021-06-01 00:00:00' "$case_dir/tie_a" "$case_dir/tie_b"
  touch -d '2022-01-01 00:00:00' "$case_dir/real/child"
}

setup_qe_empty() {
  local case_dir=$2
  mkdir -p "$case_dir"
}

setup_qe_files_only() {
  local case_dir=$2
  mkdir -p "$case_dir"
  printf 'x' > "$case_dir/a.txt"
  printf 'y' > "$case_dir/b.txt"
}

setup_qe_nested() {
  local case_dir=$2
  mkdir -p "$case_dir/deep/work/one" "$case_dir/deep/work/two"
  touch -d '2020-02-02 00:00:00' "$case_dir/deep/work/one"
  touch -d '2020-03-03 00:00:00' "$case_dir/deep/work/two"
}

if selected qe; then
  section "qe"

  SETUP=setup_qe_tree
  compare "qe: newest subdirectory" "$BASH_BIN" qe "$QE_FAKES" -- || true
  compare "qe: explicit dot start" "$BASH_BIN" qe "$QE_FAKES" -- . || true
  compare "qe: start by relative path" "$BASH_BIN" qe "$QE_FAKES" -- real || true
  compare "qe: nested relative start" "$BASH_BIN" qe "$QE_FAKES" -- "real/child" || true
  compare "qe: symlinked start keeps the logical path" "$BASH_BIN" qe "$QE_FAKES" -- link || true
  compare "qe: empty argument means dot" "$BASH_BIN" qe "$QE_FAKES" -- "" || true
  compare "qe: extra arguments are ignored" "$BASH_BIN" qe "$QE_FAKES" -- . ignored || true
  compare "qe: start is a file" "$BASH_BIN" qe "$QE_FAKES" -- file.txt || true
  compare "qe: missing start" "$BASH_BIN" qe "$QE_FAKES" -- does-not-exist || true

  SETUP=setup_qe_empty
  compare "qe: empty directory" "$BASH_BIN" qe "$QE_FAKES" -- || true

  SETUP=setup_qe_files_only
  compare "qe: no subdirectories" "$BASH_BIN" qe "$QE_FAKES" -- || true

  SETUP=setup_qe_nested
  compare "qe: dotdot start" "$BASH_BIN" qe "$QE_FAKES" -- deep/work/.. || true
  compare "qe: parent relative start" "$BASH_BIN" qe "$QE_FAKES" -- deep/../deep/work || true
fi

printf '\n%d checks, %d failed\n' "$CHECKS" "$FAILED"
exit "$FAILED"
