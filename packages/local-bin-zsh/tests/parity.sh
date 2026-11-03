#!/usr/bin/env bash
# Parity harness: run the shipped zsh helpers and the Rust ports side by side
# against the same fake external tools, and compare every observable: exit
# status, stdout bytes, stderr bytes, `~/tmp/mpv.log`, and the argv/stdin each
# fake received.
#
#   tests/parity.sh [--bin-dir DIR] [--originals-dir DIR] [--iommu-live]
#
# Env: CARGO_TARGET_DIR selects the target directory (default: ../target);
#      LOCAL_BIN_ZSH_BIN overrides the directory holding the built binaries.
#      LOCAL_BIN_ZSH_ORIGINALS overrides the source shell directory.
#      ZSH_BIN overrides the zsh used for the originals.
#
# The fakes are shell scripts first on an otherwise empty PATH; HOME, XDG and
# TMPDIR point into a temporary tree. The suite never touches the real music
# library, ~/dw or /tmp sockets: fd/fzf/vicinae/mpv/zathura are fakes and the
# selections are supplied through their environment.
#
# --iommu-live additionally compares the two binaries against the host's
# read-only /sys/kernel/iommu_groups (listing and [RESET] markers only; nothing
# is written). It is off by default so the default run is hermetic and does not
# depend on the host having IOMMU groups.
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/.." && pwd)
REPO=$(cd -- "$ROOT/../.." && pwd)
ORIGINALS=${LOCAL_BIN_ZSH_ORIGINALS:-$REPO/packages/local-bin/bin}
BIN_DIR=${LOCAL_BIN_ZSH_BIN:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}
IOMMU_LIVE=0

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
    --iommu-live)
      IOMMU_LIVE=1
      shift
      ;;
    -h | --help)
      sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "parity: unknown argument '$1'" >&2
      exit 2
      ;;
  esac
done

ZSH=$(command -v "${ZSH_BIN:-zsh}" || true)
SH_BIN=$(command -v sh)
for tool in "$ZSH" "$SH_BIN"; do
  [ -n "$tool" ] || {
    echo "parity: bash and sh are required" >&2
    exit 2
  }
done
for tool in dirname cat sed diff mktemp cp ln chmod find; do
  command -v "$tool" > /dev/null 2>&1 || {
    echo "parity: missing required utility: $tool" >&2
    exit 2
  }
done

WORK=$(mktemp -d "${TMPDIR:-/tmp}/local-bin-zsh-parity.XXXXXX")
cleanup() { rm -rf -- "$WORK"; }
trap cleanup EXIT

mkdir -p "$WORK/originals" "$WORK/home/.cache" "$WORK/home/.config" \
  "$WORK/home/.cache/music-index" "$WORK/home/vid" "$WORK/home/bin" \
  "$WORK/tmp" "$WORK/case" "$WORK/fakes" "$WORK/utils" "$WORK/music" \
  "$WORK/music-ren"

# --- originals -------------------------------------------------------------
# The sources are re-read from the working tree; if the ports have already
# replaced them, recover the last committed copies.
recover() {
  local name=$1
  local source=$ORIGINALS/$name
  if [ -r "$source" ]; then
    cp -- "$source" "$WORK/originals/$name"
    return 0
  fi
  local rel="packages/local-bin/bin/$name"
  local revision
  revision=$(git -C "$REPO" log --all --format=%H -1 -- "$rel" 2> /dev/null || true)
  [ -n "$revision" ] || return 1
  git -C "$REPO" show "$revision:$rel" > "$WORK/originals/$name" 2> /dev/null || return 1
  return 0
}

for name in iommu-info music-rename read_documents pl music-tui; do
  recover "$name" || {
    echo "parity: cannot find the original $name" >&2
    exit 2
  }
  chmod +x "$WORK/originals/$name"
done
recover _localbin.sh || {
  echo "parity: cannot find the original _localbin.sh" >&2
  exit 2
}

for program in iommu-info music-rename read_documents pl music-tui; do
  [ -x "$BIN_DIR/$program" ] || {
    echo "parity: binary not executable: $BIN_DIR/$program" >&2
    echo "parity: run cargo build first, or pass --bin-dir DIR" >&2
    exit 2
  }
done

# Utilities the shell originals call for their own housekeeping. None of them
# is under test, and each side gets the same real binaries.
for tool in zsh sh sed cat dirname basename find realpath xargs awk cut rg du stat \
  python3 wc tail head mkdir lspci; do
  path=$(command -v "$tool" 2> /dev/null || true)
  [ -n "$path" ] && ln -s "$path" "$WORK/utils/$tool"
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
  FAILED=$((FAILED + 1))
  printf 'FAIL  %s\n' "$1" >&2
}
skip() {
  SKIPPED=$((SKIPPED + 1))
  printf 'SKIP  %s\n' "$1"
}
section() { printf '\n== %s ==\n' "$1"; }

# --- fakes -----------------------------------------------------------------
# One fake per external tool. Each logs its own argv (one ARG line per argv
# element, so multi-line arguments survive) and its stdin under
# $FAKE_LOG_DIR/<tool>.{argv,stdin}; behaviour comes from FAKE_<TOOL>_* env.
make_fake() {
  local tool=$1 prefix=$2
  cat > "$WORK/fakes/$tool" << EOF
#!/bin/sh
{ printf '%s\n' "$tool"; for a in "\$@"; do printf 'ARG %s\n' "\$a"; done; } >> "\$FAKE_LOG_DIR/$tool.argv"
cat > "\$FAKE_LOG_DIR/$tool.stdin"
printf '%s' "\${FAKE_${prefix}_OUT-}"
printf '%s' "\${FAKE_${prefix}_ERR-}" >&2
exit "\${FAKE_${prefix}_CODE:-0}"
EOF
  chmod +x "$WORK/fakes/$tool"
}

for spec in fd:FD fzf:FZF vicinae:VICINAE mpv:MPV wl-copy:WL_COPY zathura:ZATHURA \
  music-similar:MUSIC_SIMILAR music-highlevel:MUSIC_HIGHLEVEL albumdetails:ALBUMDETAILS \
  ren:REN mv:MV nc:NC socat:SOCAT du:DU stat:STAT lspci:LSPCI vid-info:VID_INFO \
  vset:VSET amixer:AMIXER rg:RG; do
  make_fake "${spec%%:*}" "${spec#*:}"
done

# `fd` distinguishes its plain listing from the `--exec du` size request.
cat > "$WORK/fakes/fd" << 'EOF'
#!/bin/sh
{ printf 'fd\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/fd.argv"
cat > "$FAKE_LOG_DIR/fd.stdin"
exec_mode=0
for a in "$@"; do [ "$a" = "--exec" ] && exec_mode=1; done
if [ "$exec_mode" = 1 ]; then
  printf '%s' "${FAKE_FD_EXEC_OUT-}"
else
  printf '%s' "${FAKE_FD_OUT-}"
fi
printf '%s' "${FAKE_FD_ERR-}" >&2
exit "${FAKE_FD_CODE:-0}"
EOF

# `fzf` walks a sequence file, one output line per invocation.
cat > "$WORK/fakes/fzf" << 'EOF'
#!/bin/sh
n=0
[ -f "$FAKE_LOG_DIR/fzf.count" ] && n=$(cat "$FAKE_LOG_DIR/fzf.count")
n=$((n + 1))
printf '%s' "$n" > "$FAKE_LOG_DIR/fzf.count"
{ printf 'fzf\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/fzf.argv"
cat > "$FAKE_LOG_DIR/fzf.stdin.$n"
if [ -n "${FAKE_FZF_SEQ_FILE-}" ]; then
  sed -n "${n}p" "$FAKE_FZF_SEQ_FILE"
fi
printf '%s' "${FAKE_FZF_EXTRA-}"
exit "${FAKE_FZF_CODE:-0}"
EOF

# `playerctl` answers the `-l` probe separately from `metadata`.
cat > "$WORK/fakes/playerctl" << 'EOF'
#!/bin/sh
{ printf 'playerctl\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/playerctl.argv"
cat > "$FAKE_LOG_DIR/playerctl.stdin"
if [ "$1" = "-l" ]; then
  exit "${FAKE_PLAYERCTL_LIST_CODE:-1}"
fi
printf '%s' "${FAKE_PLAYERCTL_OUT-}"
printf '%s' "${FAKE_PLAYERCTL_ERR-}" >&2
exit "${FAKE_PLAYERCTL_CODE:-0}"
EOF

chmod +x "$WORK/fakes/"*

# A fake PATH that omits the named tools (the utilities directory is appended
# by `invoke`, so a tool living there would still be found; these are all
# tool-under-test names that exist only in the fakes directory).
fake_path_without() {
  local directory
  directory=$WORK/fakes-minus-$(printf '%s-' "$@" | tr ' /' '__')
  mkdir -p "$directory"
  rm -f "$directory"/*
  local tool file
  for file in "$WORK/fakes"/*; do
    tool=$(basename "$file")
    local keep=1
    local omitted
    for omitted in "$@"; do
      [ "$tool" = "$omitted" ] && keep=0
    done
    [ "$keep" = 1 ] && ln -s "$file" "$directory/$tool"
  done
  printf '%s' "$directory"
}

BASE_FAKES=$WORK/fakes

# Same, but starting from an explicit tool set (music-rename must not see the
# fake rg, because its text extraction is native in the port while the original
# calls the real rg).
fake_path_without_from() {
  local source=$1
  shift
  local directory
  directory=$WORK/fakes-minus-from-$(printf '%s-' "$@" | tr ' /' '__')
  mkdir -p "$directory"
  rm -f "$directory"/*
  local tool file
  for file in "$source"/*; do
    tool=$(basename "$file")
    local keep=1
    local omitted
    for omitted in "$@"; do
      [ "$tool" = "$omitted" ] && keep=0
    done
    [ "$keep" = 1 ] && ln -s "$file" "$directory/$tool"
  done
  printf '%s' "$directory"
}

# --- invocation and comparison --------------------------------------------
invoke() {
  local _side=$1 interpreter=$2 program=$3 fake_path=$4 side_log=$5
  shift 5
  local -a overrides=()
  while [ "${1:-}" != "--" ]; do
    overrides+=("$1")
    shift
  done
  shift
  local -a assignments=(
    PATH="$fake_path:$WORK/utils"
    HOME="$WORK/home"
    TMPDIR="$WORK/tmp"
    XDG_CACHE_HOME="$WORK/home/.cache"
    XDG_CONFIG_HOME="$WORK/home/.config"
    XDG_DATA_HOME="$WORK/home/.local/share"
    XDG_STATE_HOME="$WORK/home/.local/state"
    LANG=C
    LC_ALL=C
    __NIXOS_SET_ENVIRONMENT_DONE=1
    __ETC_PROFILE_DONE=1
    FAKE_LOG_DIR="$side_log"
  )
  assignments+=("${overrides[@]}")
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
    -e "s|$WORK|WORK|g"
}

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

  local o_log="$WORK/o.log" r_log="$WORK/r.log"
  rm -rf "$o_log" "$r_log" "$WORK/home/tmp/mpv.log" "$WORK/o.mpvlog" "$WORK/r.mpvlog"
  mkdir -p "$o_log" "$r_log"
  mkdir -p "$WORK/home/tmp"

  local original_status rust_status
  set +e
  (cd "$WORK/case" && invoke o "$interpreter" "$original" "$fake_path" "$o_log" "${overrides[@]}" -- "${arguments[@]}") \
    > "$WORK/o.out" 2> "$WORK/o.err"
  original_status=$?
  [ -f "$WORK/home/tmp/mpv.log" ] && mv "$WORK/home/tmp/mpv.log" "$WORK/o.mpvlog"
  (cd "$WORK/case" && invoke r direct "$rust" "$fake_path" "$r_log" "${overrides[@]}" -- "${arguments[@]}") \
    > "$WORK/r.out" 2> "$WORK/r.err"
  rust_status=$?
  [ -f "$WORK/home/tmp/mpv.log" ] && mv "$WORK/home/tmp/mpv.log" "$WORK/r.mpvlog"
  if [ "${SETTLE:-0}" = 1 ]; then sleep 0.5; fi
  set -e

  local ok=1 detail=""
  if [ "$original_status" -ne "$rust_status" ]; then
    ok=0
    detail+="  exit: original=$original_status rust=$rust_status"$'\n'
  fi
  local stream o_file r_file output
  for stream in out err mpvlog; do
    o_file=$WORK/o.$stream
    r_file=$WORK/r.$stream
    if [ ! -f "$o_file" ] && [ ! -f "$r_file" ]; then
      continue
    fi
    output=$(diff -u \
      <(artifact "$o_file" | normalize "$original" "$rust") \
      <(artifact "$r_file" | normalize "$original" "$rust") || true)
    if [ -n "$output" ]; then
      ok=0
      detail+="  $stream:"$'\n'"$output"$'\n'
    fi
  done
  # Per-tool argv/stdin logs, union of both sides.
  local names name
  names=$({
    ls -1 "$o_log" 2> /dev/null || true
    ls -1 "$r_log" 2> /dev/null || true
  } | sort -u)
  for name in $names; do
    output=$(diff -u \
      <(artifact "$o_log/$name") \
      <(artifact "$r_log/$name") || true)
    if [ -n "$output" ]; then
      ok=0
      detail+="  log/$name:"$'\n'"$output"$'\n'
    fi
  done

  if [ "$ok" = 1 ]; then
    pass "$label"
  else
    fail "$label"
    printf '%s' "$detail" >&2
  fi
}

ORIG=$WORK/originals
BIN=$BIN_DIR

# --- fixtures --------------------------------------------------------------
printf 'audio' > "$WORK/case/track.flac"
mkdir -p "$WORK/case/ArtistDir"
printf 'audio' > "$WORK/case/ArtistDir/track.flac"
mkdir -p "$WORK/case/ArtistDir/nested"
printf 'audio' > "$WORK/case/ArtistDir/nested/two.flac"

mkdir -p "$WORK/music/a" "$WORK/music/b"
printf 'x' > "$WORK/music/a/one.flac"
printf 'x' > "$WORK/music/a/two.flac"
printf 'x' > "$WORK/music/b/three.mp3"

printf '{"count": 42, "dim": 128}\n' > "$WORK/home/.cache/music-index/meta.json"
printf 'ANN' > "$WORK/home/.cache/music-index/index.ann"
printf '{"path": "/m/ArtistA/Album/x.mp3"}\n{"path": "/m/ArtistA/Album2/y.flac"}\n{"path": "/m/ArtistB/z.mp3"}\n{"path": "/m/nopath.jsonl"}\n' \
  > "$WORK/home/.cache/music-index/tracks.jsonl"

# --- iommu-info ------------------------------------------------------------
section "iommu-info"
if [ "$IOMMU_LIVE" = 1 ]; then
  compare "iommu-info: live listing" direct "$ORIG/iommu-info" "$BIN/iommu-info" "$WORK/utils" --
  compare "iommu-info: live reset markers" direct "$ORIG/iommu-info" "$BIN/iommu-info" "$WORK/utils" -- reset
  compare "iommu-info: live r prefix" direct "$ORIG/iommu-info" "$BIN/iommu-info" "$WORK/utils" -- r
else
  skip "iommu-info: live listing (pass --iommu-live)"
  skip "iommu-info: live reset markers (pass --iommu-live)"
  skip "iommu-info: live r prefix (pass --iommu-live)"
fi
compare "iommu-info: --help" direct "$ORIG/iommu-info" "$BIN/iommu-info" "$BASE_FAKES" -- --help
compare "iommu-info: -h" direct "$ORIG/iommu-info" "$BIN/iommu-info" "$BASE_FAKES" -- -h
if [ "$IOMMU_LIVE" = 1 ]; then
  compare "iommu-info: help word lists groups" direct "$ORIG/iommu-info" "$BIN/iommu-info" "$WORK/utils" -- help
else
  skip "iommu-info: help word lists groups (pass --iommu-live)"
fi

# --- read_documents --------------------------------------------------------
section "read_documents"
RD_FAKES=$WORK/fakes-read-documents
rm -rf "$RD_FAKES"
mkdir -p "$RD_FAKES"
for tool in fd vicinae zathura; do ln -s "$BASE_FAKES/$tool" "$RD_FAKES/$tool"; done
RD_NO_FD=$(fake_path_without fd)
RD_NO_VICINAE=$(fake_path_without vicinae)
RD_NO_ZATHURA=$(fake_path_without zathura)

compare "read_documents: --help" direct "$ORIG/read_documents" "$BIN/read_documents" "$RD_FAKES" -- --help
compare "read_documents: one document" direct "$ORIG/read_documents" "$BIN/read_documents" "$RD_FAKES" \
  FAKE_FD_OUT=$'a.pdf\nb.pdf' FAKE_VICINAE_OUT='b.pdf' --
compare "read_documents: cancel keeps status 1" direct "$ORIG/read_documents" "$BIN/read_documents" "$RD_FAKES" \
  FAKE_FD_OUT=$'a.pdf\nb.pdf' FAKE_VICINAE_OUT='' --
compare "read_documents: multi-line selection is one argv" direct "$ORIG/read_documents" "$BIN/read_documents" "$RD_FAKES" \
  FAKE_FD_OUT=$'a.pdf\nb.pdf' FAKE_VICINAE_OUT=$'a.pdf\nb.pdf' --
compare "read_documents: fd failure is silent" direct "$ORIG/read_documents" "$BIN/read_documents" "$RD_FAKES" \
  FAKE_FD_CODE=1 FAKE_VICINAE_OUT='' --
compare "read_documents: missing fd" direct "$ORIG/read_documents" "$BIN/read_documents" "$RD_NO_FD" \
  FAKE_VICINAE_OUT='' --
compare "read_documents: missing vicinae" direct "$ORIG/read_documents" "$BIN/read_documents" "$RD_NO_VICINAE" --
compare "read_documents: missing zathura" direct "$ORIG/read_documents" "$BIN/read_documents" "$RD_NO_ZATHURA" \
  FAKE_FD_OUT='a.pdf' FAKE_VICINAE_OUT='a.pdf' --

# --- pl --------------------------------------------------------------------
section "pl"
PL_FAKES=$WORK/fakes-pl
rm -rf "$PL_FAKES"
mkdir -p "$PL_FAKES"
for tool in fd fzf vicinae wl-copy mpv vid-info rg; do ln -s "$BASE_FAKES/$tool" "$PL_FAKES/$tool"; done
# rg is a real utility in the fallback case; keep it out of the fakes there.
PL_NO_FD=$(fake_path_without fd)
PL_NO_FZF=$(fake_path_without fzf)
PL_NO_MPV=$(fake_path_without mpv)
PL_NO_VICINAE=$(fake_path_without vicinae)
PL_NO_WLCOPY=$(fake_path_without wl-copy)

printf 'video' > "$WORK/home/vid/one.mp4"
printf 'video' > "$WORK/home/vid/two.mp4"

compare "pl: --help" direct "$ORIG/pl" "$BIN/pl" "$PL_FAKES" -- --help
compare "pl: fzf multi mixed paths" direct "$ORIG/pl" "$BIN/pl" "$PL_FAKES" \
  FAKE_FD_OUT=$'one.mp4\nsub/two.mp4' FAKE_FZF_OUT=$'one.mp4\n/tmp/abs.mp4\n\nsub/two.mp4' --
compare "pl: fzf no newline at end" direct "$ORIG/pl" "$BIN/pl" "$PL_FAKES" \
  FAKE_FD_OUT='one.mp4' FAKE_FZF_OUT='one.mp4' --
compare "pl: fzf cancel" direct "$ORIG/pl" "$BIN/pl" "$PL_FAKES" \
  FAKE_FD_OUT='one.mp4' FAKE_FZF_CODE=130 --
compare "pl: XDG_VIDEOS_DIR" direct "$ORIG/pl" "$BIN/pl" "$PL_FAKES" \
  XDG_VIDEOS_DIR="$WORK/home/vid" FAKE_FZF_OUT='one.mp4' --
compare "pl: dmenu one candidate skips vicinae" direct "$ORIG/pl" "$BIN/pl" "$PL_FAKES" \
  FAKE_FD_OUT='one.mp4' FAKE_VICINAE_OUT='' -- dmenu
compare "pl: dmenu several candidates" direct "$ORIG/pl" "$BIN/pl" "$PL_FAKES" \
  FAKE_FD_OUT=$'one.mp4\ntwo.mp4' FAKE_VICINAE_OUT='two.mp4' -- dmenu
compare "pl: dmenu cancel" direct "$ORIG/pl" "$BIN/pl" "$PL_FAKES" \
  FAKE_FD_OUT=$'one.mp4\ntwo.mp4' FAKE_VICINAE_OUT='' -- vicinae
compare "pl: dmenu empty listing" direct "$ORIG/pl" "$BIN/pl" "$PL_FAKES" -- vicinae
compare "pl: 1st_level max depth" direct "$ORIG/pl" "$BIN/pl" "$PL_FAKES" \
  FAKE_FD_OUT='one.mp4' FAKE_FZF_OUT='' -- 1st_level "$WORK/home/vid"
compare "pl: 1st_level with dmenu" direct "$ORIG/pl" "$BIN/pl" "$PL_FAKES" \
  FAKE_FD_OUT='one.mp4' FAKE_VICINAE_OUT='one.mp4' -- dmenu 1st_level "$WORK/home/vid"
compare "pl: video mode" direct "$ORIG/pl" "$BIN/pl" "$PL_FAKES" \
  FAKE_FD_OUT='one.mp4' FAKE_VICINAE_OUT='one.mp4' -- video "$WORK/home/vid"
compare "pl: video cancel" direct "$ORIG/pl" "$BIN/pl" "$PL_FAKES" \
  FAKE_FD_OUT='one.mp4' FAKE_VICINAE_OUT='' -- video "$WORK/home/vid"
compare "pl: video default directory" direct "$ORIG/pl" "$BIN/pl" "$PL_FAKES" \
  FAKE_FD_OUT='x.mp4' FAKE_VICINAE_OUT='' -- video
compare "pl: cmd passthrough" direct "$ORIG/pl" "$BIN/pl" "$PL_FAKES" \
  FAKE_PLAYERCTL_CODE=3 -- cmd play-pause
compare "pl: vol mute through vset" direct "$ORIG/pl" "$BIN/pl" "$PL_FAKES" \
  FAKE_VSET_CODE=0 -- vol mute
compare "pl: vol mute amixer fallback" direct "$ORIG/pl" "$BIN/pl" "$PL_FAKES" \
  FAKE_VSET_CODE=1 FAKE_AMIXER_CODE=0 -- vol mute
compare "pl: vol unmute amixer fallback" direct "$ORIG/pl" "$BIN/pl" "$PL_FAKES" \
  FAKE_VSET_CODE=1 FAKE_AMIXER_CODE=0 -- vol unmute
compare "pl: vol unknown action" direct "$ORIG/pl" "$BIN/pl" "$PL_FAKES" -- vol bogus
compare "pl: missing fd falls back to rg" direct "$ORIG/pl" "$BIN/pl" "$PL_NO_FD" \
  FAKE_RG_OUT=$'r1.mp4\nr2.mp4' FAKE_FZF_OUT='' --
compare "pl: missing fzf" direct "$ORIG/pl" "$BIN/pl" "$PL_NO_FZF" --
compare "pl: missing mpv writes mpv.log" direct "$ORIG/pl" "$BIN/pl" "$PL_NO_MPV" \
  FAKE_FD_OUT='one.mp4' FAKE_FZF_OUT='one.mp4' --
compare "pl: missing wl-copy" direct "$ORIG/pl" "$BIN/pl" "$PL_NO_WLCOPY" \
  FAKE_FD_OUT='one.mp4' FAKE_FZF_OUT='one.mp4' --
compare "pl: missing vicinae in dmenu" direct "$ORIG/pl" "$BIN/pl" "$PL_NO_VICINAE" \
  FAKE_FD_OUT=$'one.mp4\ntwo.mp4' -- dmenu
compare "pl: missing vicinae in video" direct "$ORIG/pl" "$BIN/pl" "$PL_NO_VICINAE" \
  FAKE_FD_OUT='one.mp4' -- video "$WORK/home/vid"
# vid-info is optional: run it only when the fake is executable, and wait for
# the two background jobs to land before comparing.
cp "$BASE_FAKES/vid-info" "$WORK/home/bin/vid-info"
chmod +x "$WORK/home/bin/vid-info"
SETTLE=1
compare "pl: vid-info warm-up" direct "$ORIG/pl" "$BIN/pl" "$PL_FAKES" \
  FAKE_FD_OUT=$'one.mp4\nsub/two.mp4' FAKE_FZF_OUT=$'one.mp4\nsub/two.mp4' -- 1st_level "$WORK/home/vid"
SETTLE=0
rm -f "$WORK/home/bin/vid-info"

# --- music-rename ----------------------------------------------------------
section "music-rename"
RN_FAKES=$WORK/fakes-music-rename
rm -rf "$RN_FAKES"
mkdir -p "$RN_FAKES"
for tool in albumdetails ren mv nc socat; do ln -s "$BASE_FAKES/$tool" "$RN_FAKES/$tool"; done
RN_NO_NC=$(fake_path_without_from "$RN_FAKES" nc)
RN_NO_NC_SOCAT=$(fake_path_without_from "$RN_FAKES" nc socat)
RN_NO_ALBUM=$(fake_path_without_from "$RN_FAKES" albumdetails)

FULL=$'Artist: The Artist\nYear: 2026\nAlbum: The Album'
compare "music-rename: --help" direct "$ORIG/music-rename" "$BIN/music-rename" "$RN_FAKES" -- --help
compare "music-rename: no arguments" direct "$ORIG/music-rename" "$BIN/music-rename" "$RN_FAKES" --
compare "music-rename: spaces only" direct "$ORIG/music-rename" "$BIN/music-rename" "$RN_FAKES" -- '   '
compare "music-rename: files mode" direct "$ORIG/music-rename" "$BIN/music-rename" "$RN_FAKES" \
  XDG_MUSIC_DIR="$WORK/music-ren" FAKE_ALBUMDETAILS_OUT="$FULL" -- f "$WORK/case/ArtistDir/track.flac"
compare "music-rename: two files go to one albumdetails" direct "$ORIG/music-rename" "$BIN/music-rename" "$RN_FAKES" \
  XDG_MUSIC_DIR="$WORK/music-ren" FAKE_ALBUMDETAILS_OUT="$FULL" \
  -- f "$WORK/case/ArtistDir/track.flac" "$WORK/case/track.flac"
compare "music-rename: default file mode" direct "$ORIG/music-rename" "$BIN/music-rename" "$RN_FAKES" \
  XDG_MUSIC_DIR="$WORK/music-ren" FAKE_ALBUMDETAILS_OUT="$FULL" -- "$WORK/case/ArtistDir/track.flac"
compare "music-rename: directory mode" direct "$ORIG/music-rename" "$BIN/music-rename" "$RN_FAKES" \
  XDG_MUSIC_DIR="$WORK/music-ren" FAKE_ALBUMDETAILS_OUT="$FULL" -- "$WORK/case/ArtistDir"
compare "music-rename: empty albumdetails output" direct "$ORIG/music-rename" "$BIN/music-rename" "$RN_FAKES" \
  XDG_MUSIC_DIR="$WORK/music-ren" FAKE_ALBUMDETAILS_OUT='' -- f "$WORK/case/ArtistDir/track.flac"
compare "music-rename: slash and spaces" direct "$ORIG/music-rename" "$BIN/music-rename" "$RN_FAKES" \
  XDG_MUSIC_DIR="$WORK/music-ren" \
  FAKE_ALBUMDETAILS_OUT=$'Artist:  A / B  \nYear:  2026 x\nAlbum:  Al/bum One  ' -- f "$WORK/case/ArtistDir/track.flac"
for year in 1800 1889 1890 1899 1900 1975 1989 1990 1995 1999 2000 2001 2009 2010 2026 2035 2036 2050; do
  compare "music-rename: year $year" direct "$ORIG/music-rename" "$BIN/music-rename" "$RN_FAKES" \
    XDG_MUSIC_DIR="$WORK/music-ren" \
    FAKE_ALBUMDETAILS_OUT="Artist: A"$'\n'"Year: $year"$'\n'"Album: B" -- f "$WORK/case/ArtistDir/track.flac"
done
compare "music-rename: no year" direct "$ORIG/music-rename" "$BIN/music-rename" "$RN_FAKES" \
  XDG_MUSIC_DIR="$WORK/music-ren" FAKE_ALBUMDETAILS_OUT=$'Artist: A\nAlbum: B' -- f "$WORK/case/ArtistDir/track.flac"
compare "music-rename: missing albumdetails" direct "$ORIG/music-rename" "$BIN/music-rename" "$RN_NO_ALBUM" \
  XDG_MUSIC_DIR="$WORK/music-ren" -- f "$WORK/case/ArtistDir/track.flac"
compare "music-rename: mv failure continues" direct "$ORIG/music-rename" "$BIN/music-rename" "$RN_FAKES" \
  XDG_MUSIC_DIR="$WORK/music-ren" FAKE_MV_CODE=1 FAKE_ALBUMDETAILS_OUT="$FULL" \
  -- f "$WORK/case/ArtistDir/track.flac"
compare "music-rename: ren failure continues" direct "$ORIG/music-rename" "$BIN/music-rename" "$RN_FAKES" \
  XDG_MUSIC_DIR="$WORK/music-ren" FAKE_REN_CODE=1 FAKE_ALBUMDETAILS_OUT="$FULL" \
  -- f "$WORK/case/ArtistDir/track.flac"
compare "music-rename: XDG_MUSIC_DIR unset" direct "$ORIG/music-rename" "$BIN/music-rename" "$RN_FAKES" \
  XDG_MUSIC_DIR= FAKE_ALBUMDETAILS_OUT="$FULL" -- f "$WORK/case/ArtistDir/track.flac"

# Current-track mode reads a fake MPD socket; never the real one.
mkdir -p "$WORK/music-ren/ArtistDir"
printf 'audio' > "$WORK/music-ren/ArtistDir/track.flac"
compare "music-rename: current from nc" direct "$ORIG/music-rename" "$BIN/music-rename" "$RN_FAKES" \
  XDG_MUSIC_DIR="$WORK/music-ren" FAKE_ALBUMDETAILS_OUT="$FULL" \
  FAKE_NC_OUT=$'file: ArtistDir/track.flac\nOK\n' -- current
compare "music-rename: MPD password host" direct "$ORIG/music-rename" "$BIN/music-rename" "$RN_FAKES" \
  MPD_HOST='pw@localhost' XDG_MUSIC_DIR="$WORK/music-ren" FAKE_ALBUMDETAILS_OUT="$FULL" \
  FAKE_NC_OUT=$'file: ArtistDir/track.flac\n' -- current
compare "music-rename: MPD_PORT" direct "$ORIG/music-rename" "$BIN/music-rename" "$RN_FAKES" \
  MPD_PORT=6611 XDG_MUSIC_DIR="$WORK/music-ren" FAKE_ALBUMDETAILS_OUT="$FULL" \
  FAKE_NC_OUT=$'file: ArtistDir/track.flac\n' -- current
compare "music-rename: current without a track" direct "$ORIG/music-rename" "$BIN/music-rename" "$RN_FAKES" \
  XDG_MUSIC_DIR="$WORK/music-ren" FAKE_NC_OUT='' -- c
compare "music-rename: socat fallback" direct "$ORIG/music-rename" "$BIN/music-rename" "$RN_NO_NC" \
  XDG_MUSIC_DIR="$WORK/music-ren" FAKE_ALBUMDETAILS_OUT="$FULL" \
  FAKE_SOCAT_OUT=$'file: ArtistDir/track.flac\n' -- current
compare "music-rename: neither nc nor socat" direct "$ORIG/music-rename" "$BIN/music-rename" "$RN_NO_NC_SOCAT" \
  XDG_MUSIC_DIR="$WORK/music-ren" -- current

# --- music-tui -------------------------------------------------------------
section "music-tui"
TUI_FAKES=$WORK/fakes-music-tui
rm -rf "$TUI_FAKES"
mkdir -p "$TUI_FAKES"
for tool in fd fzf music-similar music-highlevel mpv playerctl; do ln -s "$BASE_FAKES/$tool" "$TUI_FAKES/$tool"; done
TUI_NO_SIMILAR=$(fake_path_without music-similar)
TUI_NO_HIGHLEVEL=$(fake_path_without music-highlevel)
TUI_NO_MPV=$(fake_path_without mpv)
TUI_NO_FD=$(fake_path_without fd)

SEQ=$WORK/sequence
printf '/tmp/probe/music/a/one.flac\n0.9\t/tmp/probe/music/a/two.flac\n/tmp/probe/music/a/two.flac\n0.9\t/tmp/probe/music/a/two.flac\n\n' > "$SEQ"
SEQ_SIMILAR=$WORK/sequence-similar
printf '0.9\t/tmp/probe/music/a/one.flac\n0.8\t/tmp/probe/music/a/two.flac\n' > "$SEQ_SIMILAR"
SEQ_ONE=$WORK/sequence-one
printf '0.9\t/tmp/probe/music/a/one.flac\n' > "$SEQ_ONE"
SEQ_MENU=$WORK/sequence-menu
printf 'profile\n' > "$SEQ_MENU"
SEQ_BOGUS=$WORK/sequence-bogus
printf 'bogus\n' > "$SEQ_BOGUS"
SEQ_CLASSIFY=$WORK/sequence-classify
printf '/tmp/probe/music/a/one.flac\n' > "$SEQ_CLASSIFY"

compare "music-tui: --help" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_FAKES" -- --help
compare "music-tui: unknown mode" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_FAKES" -- bogus
compare "music-tui: menu cancel" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_FAKES" -- ''
compare "music-tui: menu bogus choice" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_FAKES" \
  FAKE_FZF_SEQ_FILE="$SEQ_BOGUS" --
compare "music-tui: menu profile" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_FAKES" \
  FAKE_PLAYERCTL_LIST_CODE=1 FAKE_FD_OUT=$'/tmp/probe/music/a/one.flac\n/tmp/probe/music/a/two.flac' \
  FAKE_FZF_SEQ_FILE="$SEQ_MENU" --
compare "music-tui: similar pick" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_FAKES" \
  FAKE_LIST_CODE=1 FAKE_PLAYERCTL_LIST_CODE=1 \
  FAKE_FD_OUT=$'/tmp/probe/music/a/one.flac\n/tmp/probe/music/a/two.flac' \
  FAKE_FZF_SEQ_FILE="$SEQ_ONE" \
  FAKE_MUSIC_SIMILAR_OUT=$'0.9\t/tmp/probe/music/a/one.flac' -- similar
compare "music-tui: similar current track" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_FAKES" \
  FAKE_PLAYERCTL_LIST_CODE=0 FAKE_PLAYERCTL_OUT='Artist - Title' \
  FAKE_FZF_SEQ_FILE="$SEQ_ONE" FAKE_MUSIC_SIMILAR_OUT=$'0.9\t/tmp/probe/music/a/one.flac' -- similar 5
compare "music-tui: similar empty results" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_FAKES" \
  FAKE_PLAYERCTL_LIST_CODE=1 FAKE_FD_OUT='/tmp/probe/music/a/one.flac' \
  FAKE_FZF_SEQ_FILE="$SEQ_ONE" FAKE_MUSIC_SIMILAR_OUT='' -- similar
compare "music-tui: similar cancel pick" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_FAKES" \
  FAKE_PLAYERCTL_LIST_CODE=1 FAKE_FD_OUT='/tmp/probe/music/a/one.flac' -- similar
compare "music-tui: similar cancel selection" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_FAKES" \
  FAKE_PLAYERCTL_LIST_CODE=0 FAKE_PLAYERCTL_OUT='Artist - Title' \
  FAKE_FZF_SEQ_FILE=/dev/null FAKE_MUSIC_SIMILAR_OUT=$'0.9\t/tmp/probe/music/a/one.flac' -- similar
compare "music-tui: similar missing file" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_FAKES" \
  FAKE_PLAYERCTL_LIST_CODE=1 FAKE_FD_OUT='/tmp/probe/music/a/one.flac' \
  FAKE_FZF_SEQ_FILE="$SEQ_ONE" FAKE_MUSIC_SIMILAR_OUT=$'0.9\t/tmp/probe/missing.flac' -- similar
compare "music-tui: similar without music-similar" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_NO_SIMILAR" -- similar
compare "music-tui: similar without mpv" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_NO_MPV" -- similar
compare "music-tui: classify argument" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_FAKES" \
  FAKE_FZF_SEQ_FILE="$SEQ_ONE" FAKE_MUSIC_HIGHLEVEL_OUT=$'tag1\ntag2' -- classify /tmp/probe/music/a/one.flac
compare "music-tui: classify pick" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_FAKES" \
  FAKE_FD_OUT='/tmp/probe/music/a/one.flac' FAKE_FZF_SEQ_FILE="$SEQ_CLASSIFY" \
  FAKE_MUSIC_HIGHLEVEL_OUT='tag' -- classify
compare "music-tui: classify missing file" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_FAKES" -- classify /missing.flac
compare "music-tui: classify without music-highlevel" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_NO_HIGHLEVEL" -- classify /tmp/probe/music/a/one.flac
compare "music-tui: profile with index" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_FAKES" \
  FAKE_PLAYERCTL_LIST_CODE=0 FAKE_PLAYERCTL_OUT='Artist - Title' \
  FAKE_FD_OUT=$'/tmp/probe/music/a/one.flac\n/tmp/probe/music/b/three.mp3' \
  FAKE_FD_EXEC_OUT=$'1.5M\t/tmp/probe/music' -- profile
compare "music-tui: profile without index" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_FAKES" \
  FAKE_PLAYERCTL_LIST_CODE=1 FAKE_FD_OUT='' -- profile
compare "music-tui: profile missing music dir" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_FAKES" \
  MUSIC_DIR="$WORK/no-music" FAKE_PLAYERCTL_LIST_CODE=1 -- profile
printf 'not json\n' > "$WORK/home/.cache/music-index/tracks.jsonl"
compare "music-tui: profile malformed tracks" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_FAKES" \
  FAKE_PLAYERCTL_LIST_CODE=1 FAKE_FD_OUT='' -- profile
printf '{"path": "/m/ArtistA/Album/x.mp3"}\n{"path": "/m/ArtistA/Album2/y.flac"}\n{"path": "/m/ArtistB/z.mp3"}\n{"path": "/m/nopath.jsonl"}\n' \
  > "$WORK/home/.cache/music-index/tracks.jsonl"
compare "music-tui: profile stats alias" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_FAKES" \
  FAKE_PLAYERCTL_LIST_CODE=1 FAKE_FD_OUT='' -- stats
compare "music-tui: interactive drill" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_FAKES" \
  FAKE_FD_OUT=$'/tmp/probe/music/a/one.flac\n/tmp/probe/music/a/two.flac' \
  FAKE_FZF_SEQ_FILE="$SEQ" \
  FAKE_MUSIC_SIMILAR_OUT=$'0.9\t/tmp/probe/music/a/two.flac' -- interactive
compare "music-tui: interactive cancel" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_FAKES" \
  FAKE_FD_OUT='/tmp/probe/music/a/one.flac' -- interactive
compare "music-tui: interactive missing tools" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_NO_SIMILAR" -- interactive
compare "music-tui: missing fd gives empty selections" direct "$ORIG/music-tui" "$BIN/music-tui" "$TUI_NO_FD" -- similar

# ---------------------------------------------------------------------------
printf '\n%d checks, %d failed, %d skipped\n' "$CHECKS" "$FAILED" "$SKIPPED"
[ "$FAILED" -eq 0 ]
