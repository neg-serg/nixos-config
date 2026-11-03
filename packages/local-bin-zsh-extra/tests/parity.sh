#!/usr/bin/env bash
# Shell-vs-Rust parity harness for the local-bin-zsh-extra ports.
#
# Runs the original zsh scripts from packages/local-bin/bin and the Rust
# binaries side by side under identical fake tools, then compares status,
# stdout, stderr, per-tool argv/stdin logs and the files each side wrote.
#
# The suite is hermetic: every tool is a fake first on PATH, HOME/XDG/TMPDIR
# point into per-side temporary trees, and the fixtures are copies. It never
# talks to GitHub, libvirt, PipeWire, MPD, sysctl, the trash or /dev/shm.
#
# Usage: tests/parity.sh [RUST_BIN_DIR]
#   RUST_BIN_DIR defaults to $CARGO_TARGET_DIR/debug or <crate>/target/debug.
#   ZSH, BIN_DIR (originals) and WORK can be overridden from the environment.
#   Set KEEP=1 to keep the temporary tree for inspection.
set -uo pipefail

CRATE_DIR=$(cd "$(dirname "$0")/.." && pwd)
REPO_DIR=$(cd "$CRATE_DIR/../.." && pwd)
BIN_DIR=${BIN_DIR:-"$REPO_DIR/packages/local-bin/bin"}
RUST_DIR=${1:-${CARGO_TARGET_DIR:-"$CRATE_DIR/target"}/debug}
ZSH=${ZSH:-$(command -v zsh || true)}

if [ -z "$ZSH" ] || [ ! -x "$ZSH" ]; then
  echo "parity: zsh is required to run the originals" >&2
  exit 2
fi
if [ ! -d "$RUST_DIR" ]; then
  echo "parity: Rust binaries not found in $RUST_DIR (run cargo build first)" >&2
  exit 2
fi

WORK=${WORK:-$(mktemp -d /tmp/local-bin-zsh-extra-parity.XXXXXX)}
if [ "${KEEP:-0}" = 1 ]; then
  echo "parity: keeping $WORK"
else
  trap 'rm -rf "$WORK"' EXIT
fi

CHECKS=0
FAILED=0
SKIPPED=0

section() { printf '\n== %s ==\n' "$*"; }
pass() {
  CHECKS=$((CHECKS + 1))
  printf 'ok   %s\n' "$*"
}
fail() {
  CHECKS=$((CHECKS + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL %s\n' "$*" >&2
}
skip() {
  SKIPPED=$((SKIPPED + 1))
  printf 'skip %s\n' "$*"
}

# ── Shared fake tools ───────────────────────────────────────────────────────

FAKES=$WORK/fakes
UTILS=$WORK/utils
mkdir -p "$FAKES" "$UTILS"

for tool in awk basename cat cut date dirname find grep head jq perl sed sort tr; do
  path=$(command -v "$tool" 2> /dev/null || true)
  if [ -n "$path" ]; then
    ln -s "$path" "$UTILS/$tool"
  fi
done

log_argv() {
  local name=$1
  shift
  {
    printf '%s\n' "$name"
    printf '%s\n' "$name" >> "$FAKE_LOG_DIR/calls.log"
    local argument
    for argument in "$@"; do printf 'ARG %s\n' "$argument"; done
  } >> "$FAKE_LOG_DIR/$name.argv"
}

drain_stdin() {
  local name=$1
  : > "$FAKE_LOG_DIR/$name.stdin"
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    printf '%s\n' "$line" >> "$FAKE_LOG_DIR/$name.stdin"
  done
}

make_fake() {
  local name=$1
  cat > "$FAKES/$name"
  chmod +x "$FAKES/$name"
}

make_fake wpctl << 'EOF'
#!/bin/sh
{
  printf 'wpctl\n'
  for a in "$@"; do printf 'ARG %s\n' "$a"; done
} >> "$FAKE_LOG_DIR/wpctl.argv"
case "$1" in
  get-volume) printf '%s' "${FAKE_WPCTL_VOLUME-}"; exit "${FAKE_WPCTL_GET_CODE:-0}" ;;
  set-volume) printf '%s' "${FAKE_WPCTL_OUT-}"; printf '%s' "${FAKE_WPCTL_ERR-}" >&2; exit "${FAKE_WPCTL_SET_CODE:-0}" ;;
esac
exit 0
EOF

make_fake mpc << 'EOF'
#!/bin/sh
{
  printf 'mpc\n'
  for a in "$@"; do printf 'ARG %s\n' "$a"; done
} >> "$FAKE_LOG_DIR/mpc.argv"
case "$2" in
  %artist%) printf '%s' "${FAKE_MPC_ARTIST-}" ;;
  %file%) printf '%s' "${FAKE_MPC_FILE-}" ;;
esac
exit "${FAKE_MPC_CODE:-0}"
EOF

make_fake mv << 'EOF'
#!/bin/sh
{
  printf 'mv\n'
  for a in "$@"; do printf 'ARG %s\n' "$a"; done
} >> "$FAKE_LOG_DIR/mv.argv"
printf '%s' "${FAKE_MV_OUT-}"
printf '%s' "${FAKE_MV_ERR-}" >&2
exit "${FAKE_MV_CODE:-0}"
EOF

make_fake swayimg << 'EOF'
#!/bin/sh
{
  printf 'swayimg\n'
  for a in "$@"; do printf 'ARG %s\n' "$a"; done
} >> "$FAKE_LOG_DIR/swayimg.argv"
file=""
previous=""
for a in "$@"; do
  if [ "$previous" = "-f" ]; then file=$a; fi
  previous=$a
done
: > "$FAKE_LOG_DIR/swayimg.list"
if [ -z "$file" ] || [ "$file" = "-" ]; then
  while IFS= read -r line || [ -n "$line" ]; do printf '%s\n' "$line" >> "$FAKE_LOG_DIR/swayimg.list"; done
else
  while IFS= read -r line || [ -n "$line" ]; do printf '%s\n' "$line" >> "$FAKE_LOG_DIR/swayimg.list"; done < "$file"
fi
exit "${FAKE_SWAYIMG_CODE:-0}"
EOF

make_fake notify-send << 'EOF'
#!/bin/sh
{
  printf 'notify-send\n'
  printf 'notify-send\n' >> "$FAKE_LOG_DIR/calls.log"
  for a in "$@"; do printf 'ARG %s\n' "$a"; done
} >> "$FAKE_LOG_DIR/notify-send.argv"
exit "${FAKE_NOTIFY_CODE:-0}"
EOF

make_fake sync << 'EOF'
#!/bin/sh
{
  printf 'sync\n'
  printf 'sync\n' >> "$FAKE_LOG_DIR/calls.log"
  for a in "$@"; do printf 'ARG %s\n' "$a"; done
} >> "$FAKE_LOG_DIR/sync.argv"
exit "${FAKE_SYNC_CODE:-0}"
EOF

make_fake sleep << 'EOF'
#!/bin/sh
{
  printf 'sleep\n'
  printf 'sleep\n' >> "$FAKE_LOG_DIR/calls.log"
  for a in "$@"; do printf 'ARG %s\n' "$a"; done
} >> "$FAKE_LOG_DIR/sleep.argv"
exit "${FAKE_SLEEP_CODE:-0}"
EOF

make_fake sudo << 'EOF'
#!/bin/sh
{
  printf 'sudo\n'
  printf 'sudo\n' >> "$FAKE_LOG_DIR/calls.log"
  for a in "$@"; do printf 'ARG %s\n' "$a"; done
} >> "$FAKE_LOG_DIR/sudo.argv"
case "${1-}" in
  sysctl)
    case "$*" in
      *vm.drop_caches=3*) exit "${FAKE_SUDO_DROP_CODE:-0}" ;;
      *vm.compact_memory=1*) exit "${FAKE_SUDO_COMPACT_CODE:-0}" ;;
      *vm.swappiness=10*) exit "${FAKE_SUDO_RESTORE_CODE:-0}" ;;
      *) exit "${FAKE_SUDO_CODE:-0}" ;;
    esac
    ;;
  *)
    exec "$@"
    ;;
esac
EOF

make_fake mkdir << 'EOF'
#!/bin/sh
{
  printf 'mkdir\n'
  printf 'mkdir\n' >> "$FAKE_LOG_DIR/calls.log"
  for a in "$@"; do printf 'ARG %s\n' "$a"; done
} >> "$FAKE_LOG_DIR/mkdir.argv"
exec "${LOCAL_BIN_ZSH_EXTRA_TEST_MKDIR:-/bin/mkdir}" "$@"
EOF

make_fake rm << 'EOF'
#!/bin/sh
{
  printf 'rm\n'
  for a in "$@"; do printf 'ARG %s\n' "$a"; done
} >> "$FAKE_LOG_DIR/rm.argv"
exec "${LOCAL_BIN_ZSH_EXTRA_TEST_RM:-/bin/rm}" "$@"
EOF

make_fake qemu-img << 'EOF'
#!/bin/sh
{
  printf 'qemu-img\n'
  for a in "$@"; do printf 'ARG %s\n' "$a"; done
} >> "$FAKE_LOG_DIR/qemu-img.argv"
previous=""
last=""
for a in "$@"; do previous=$last; last=$a; done
if [ -n "$previous" ]; then : > "$previous"; fi
exit "${FAKE_QEMU_IMG_CODE:-0}"
EOF

make_fake curl << 'EOF'
#!/bin/sh
{
  printf 'curl\n'
  for a in "$@"; do printf 'ARG %s\n' "$a"; done
} >> "$FAKE_LOG_DIR/curl.argv"
output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) output=$2; shift 2 ;;
    *) shift ;;
  esac
done
if [ -n "$output" ]; then : > "$output"; fi
exit "${FAKE_CURL_CODE:-0}"
EOF

make_fake id << 'EOF'
#!/bin/sh
{
  printf 'id\n'
  for a in "$@"; do printf 'ARG %s\n' "$a"; done
} >> "$FAKE_LOG_DIR/id.argv"
printf '%s\n' "${FAKE_ID_GROUPS:-neg libvirtd}"
exit "${FAKE_ID_CODE:-0}"
EOF

make_fake virsh << 'EOF'
#!/bin/sh
{
  printf 'virsh\n'
  for a in "$@"; do printf 'ARG %s\n' "$a"; done
} >> "$FAKE_LOG_DIR/virsh.argv"
printf '%s\n' "$3" >> "$FAKE_LOG_DIR/virsh.calls"
case "$3" in
  dominfo) exit "${FAKE_VIRSH_DOMINFO_CODE:-1}" ;;
  domstate) printf '%s' "${FAKE_VIRSH_DOMSTATE:-shut off}"; exit "${FAKE_VIRSH_DOMSTATE_CODE:-0}" ;;
  net-info) printf '%s' "${FAKE_VIRSH_NETINFO:-Active: yes}"; exit 0 ;;
  domblklist) printf '%s' "${FAKE_VIRSH_DOMBLLIST-}"; exit "${FAKE_VIRSH_DOMBLLIST_CODE:-0}" ;;
  domdisplay) printf '%s' "${FAKE_VIRSH_DOMDISPLAY-}"; exit "${FAKE_VIRSH_DOMDISPLAY_CODE:-0}" ;;
  attach-device)
    if [ -n "${FAKE_VIRSH_DEVICE_COPY-}" ]; then
      while IFS= read -r line || [ -n "$line" ]; do printf '%s\n' "$line"; done < "$5" > "$FAKE_VIRSH_DEVICE_COPY"
    fi
    exit "${FAKE_VIRSH_ATTACH_CODE:-0}"
    ;;
  detach-device) exit "${FAKE_VIRSH_DETACH_CODE:-0}" ;;
  change-media) exit "${FAKE_VIRSH_CHANGE_CODE:-0}" ;;
  undefine)
    case " $* " in
      *--remove-all-storage*) exit "${FAKE_VIRSH_REMOVE_ALL_CODE:-0}" ;;
    esac
    exit "${FAKE_VIRSH_UNDEFINE_CODE:-0}"
    ;;
  *) exit "${FAKE_VIRSH_CODE:-0}" ;;
esac
EOF

make_fake gh << 'EOF'
#!/bin/sh
{
  printf 'gh\n'
  for a in "$@"; do printf 'ARG %s\n' "$a"; done
} >> "$FAKE_LOG_DIR/gh.argv"
case "$1" in
  auth) exit "${FAKE_GH_AUTH_CODE:-0}" ;;
  api)
    case "$2" in
      --paginate)
        case "$3" in
          */comments*) printf '%s' "${FAKE_GH_COMMENTS-}"; exit "${FAKE_GH_COMMENTS_CODE:-0}" ;;
          *) printf '%s' "${FAKE_GH_ISSUES-}"; exit "${FAKE_GH_ISSUES_CODE:-0}" ;;
        esac
        ;;
      /rate_limit) printf '%s' "${FAKE_GH_RATE-}"; exit "${FAKE_GH_RATE_CODE:-0}" ;;
      *) exit "${FAKE_GH_REPO_CODE:-0}" ;;
    esac
    ;;
esac
exit 0
EOF

for name in virt-install virt-xml systemctl chown swtpm spicy remote-viewer virt-viewer looking-glass-client; do
  prefix=$(printf '%s' "$name" | tr '[:lower:]-' '[:upper:]_')
  make_fake "$name" << EOF
#!/bin/sh
{
  printf '$name\n'
  for a in "\$@"; do printf 'ARG %s\n' "\$a"; done
} >> "\$FAKE_LOG_DIR/$name.argv"
printf '%s' "\${FAKE_${prefix}_OUT-}"
printf '%s' "\${FAKE_${prefix}_ERR-}" >&2
exit "\${FAKE_${prefix}_CODE:-0}"
EOF
done

# A PATH with every fake except the named tools (utils stay available).
fake_path_without() {
  local suffix
  suffix=$(printf '%s-' "$@" | tr ' /' '__')
  local directory=$WORK/fakes-minus-$suffix
  if [ ! -d "$directory" ]; then
    mkdir -p "$directory"
    local file tool keep omitted
    for file in "$FAKES"/*; do
      tool=$(basename "$file")
      keep=1
      for omitted in "$@"; do [ "$tool" = "$omitted" ] && keep=0; done
      [ "$keep" = 1 ] && ln -s "$file" "$directory/$tool"
    done
  fi
  printf '%s' "$directory"
}

# ── Runner ──────────────────────────────────────────────────────────────────

SCRIPT=""
FAKE_PATH=""
SIDE_STDIN=/dev/null
SIDE_ENV=()
SETTLE=0

reset_sides() {
  rm -rf "$WORK/o" "$WORK/r"
  local side root
  for side in o r; do
    root=$WORK/$side
    mkdir -p "$root/case" "$root/home" "$root/logs" "$root/tmp" \
      "$root/xdg/cache" "$root/xdg/config" "$root/xdg/data" "$root/xdg/state" \
      "$root/home/.local/bin" "$root/home/.config"
  done
}

run_side() {
  local side=$1
  shift
  local root=$WORK/$side
  local -a program
  if [ "$side" = o ]; then
    program=("$ZSH" -f "$BIN_DIR/$SCRIPT")
  else
    program=("$RUST_DIR/$SCRIPT")
  fi
  (
    cd "$root/case" \
      && env -i \
        PATH="$FAKE_PATH:$UTILS" \
        HOME="$root/home" \
        TMPDIR="$root/tmp" \
        XDG_CACHE_HOME="$root/xdg/cache" \
        XDG_CONFIG_HOME="$root/xdg/config" \
        XDG_DATA_HOME="$root/xdg/data" \
        XDG_STATE_HOME="$root/xdg/state" \
        LANG=C LC_ALL=C USER=neg \
        FAKE_LOG_DIR="$root/logs" \
        LOCAL_BIN_ZSH_EXTRA_TEST_MKDIR="${LOCAL_BIN_ZSH_EXTRA_TEST_MKDIR:-$(command -v mkdir)}" \
        LOCAL_BIN_ZSH_EXTRA_TEST_RM="${LOCAL_BIN_ZSH_EXTRA_TEST_RM:-$(command -v rm)}" \
        __NIXOS_SET_ENVIRONMENT_DONE=1 __ETC_PROFILE_DONE=1 \
        "${SIDE_ENV[@]}" \
        "${program[@]}" "$@"
  ) < "$SIDE_STDIN" > "$root/out" 2> "$root/err"
  printf '%s\n' "$?" > "$root/status"
}

normalize() {
  sed -E \
    -e "s|$BIN_DIR|PROG|g" \
    -e "s|$RUST_DIR|PROG|g" \
    -e "s|$ZSH|ZSH|g" \
    -e "s|$WORK/o|ROOT|g" \
    -e "s|$WORK/r|ROOT|g" \
    -e 's|/dev/fd/[0-9]+|LISTFD|g' \
    -e 's|/proc/self/fd/[0-9]+|LISTFD|g' \
    -e 's/^ARG -$/ARG LISTFD/' \
    -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/TIMESTAMP/g' \
    -e 's/Waiting [0-9]+s/Waiting NS/g' \
    -e 's|/tmp/win-vm-shmem-[0-9]+\.xml|/tmp/win-vm-shmem-PID.xml|g' \
    -e 's|/tmp/win-vm-usb-[0-9]+\.xml|/tmp/win-vm-usb-PID.xml|g'
}

artifact_list() {
  local root=$1
  # Directory symlinks would make the content diff read a directory; their
  # effect on the tool is already visible in the argv/stdin logs.
  (cd "$root" && find case home xdg -type f 2> /dev/null | LC_ALL=C sort)
}

# Sleep seconds can differ by one between the two runs when the rate-limit
# reset is relative to "now"; sys-relief's fixed 300 still normalizes the same.
normalize_log() {
  local path=$1
  if [ ! -f "$path" ]; then
    return 0
  fi
  normalize < "$path" | sed -E 's/^ARG [0-9]+$/ARG WAIT/'
}

check_pair() {
  local label=$1
  local o_root=$WORK/o r_root=$WORK/r
  local ok=1 detail=""
  local o_status r_status
  o_status=$(cat "$o_root/status")
  r_status=$(cat "$r_root/status")
  if [ "$o_status" != "$r_status" ]; then
    ok=0
    detail+="  exit: original=$o_status rust=$r_status"$'\n'
  fi
  local stream
  for stream in out err; do
    local diff_output
    diff_output=$(diff -u \
      <(normalize < "$o_root/$stream") \
      <(normalize < "$r_root/$stream") || true)
    if [ -n "$diff_output" ]; then
      ok=0
      detail+="  $stream:"$'\n'"$diff_output"$'\n'
    fi
  done
  local names name
  names=$({
    (cd "$o_root/logs" && find . -type f -printf '%P\n')
    (cd "$r_root/logs" && find . -type f -printf '%P\n')
  } | LC_ALL=C sort -u)
  for name in $names; do
    local diff_output
    diff_output=$(diff -u \
      <(normalize_log "$o_root/logs/$name") \
      <(normalize_log "$r_root/logs/$name") || true)
    if [ -n "$diff_output" ]; then
      ok=0
      detail+="  logs/$name:"$'\n'"$diff_output"$'\n'
    fi
  done
  local o_files r_files
  o_files=$(artifact_list "$o_root")
  r_files=$(artifact_list "$r_root")
  if [ "$o_files" != "$r_files" ]; then
    ok=0
    detail+="  files:"$'\n'"$(diff -u <(printf '%s\n' "$o_files") <(printf '%s\n' "$r_files") || true)"$'\n'
  else
    local relative
    for relative in $o_files; do
      local diff_output
      diff_output=$(diff -u \
        <(normalize < "$o_root/$relative") \
        <(normalize < "$r_root/$relative") || true)
      if [ -n "$diff_output" ]; then
        ok=0
        detail+="  file/$relative:"$'\n'"$diff_output"$'\n'
      fi
    done
  fi
  if [ "$ok" = 1 ]; then
    pass "$label"
  else
    fail "$label"
    printf '%s' "$detail" >&2
  fi
}

compare() {
  local label=$1
  shift
  rm -rf "$WORK/o/logs" "$WORK/r/logs"
  mkdir -p "$WORK/o/logs" "$WORK/r/logs"
  if [ "$SETTLE" != 0 ]; then sleep "$SETTLE"; fi
  run_side o "$@"
  run_side r "$@"
  if [ "$SETTLE" != 0 ]; then sleep "$SETTLE"; fi
  check_pair "$label"
}

begin() {
  SCRIPT=$1
  FAKE_PATH=$FAKES
  SIDE_STDIN=/dev/null
  SIDE_ENV=()
  SETTLE=0
  reset_sides
}

append_sides() {
  local line=$1 side
  for side in o r; do
    printf '%s\n' "$line" >> "$WORK/$side/xdg/config/win-vm/config.sh"
  done
}

# ── vol ─────────────────────────────────────────────────────────────────────

section "vol"
begin vol
compare "vol: --help" --help
compare "vol: -h" -h
SIDE_ENV=(FAKE_WPCTL_VOLUME=$'Volume: 0.50\n')
compare "vol: +0.05" +0.05
SIDE_ENV=(FAKE_WPCTL_VOLUME=$'Volume: 0.98\n')
compare "vol: clamp at one" +0.05
SIDE_ENV=(FAKE_WPCTL_VOLUME=$'Volume: -0.5\n')
compare "vol: clamp at zero" +0
SIDE_ENV=(FAKE_WPCTL_VOLUME=$'Volume:  0.25 [MUTED]\n')
compare "vol: muted suffix" +0.05
SIDE_ENV=(FAKE_WPCTL_GET_CODE=1)
compare "vol: get-volume failure" +0.05
SIDE_ENV=(FAKE_WPCTL_VOLUME=$'Volume: 0.50\n' FAKE_WPCTL_SET_CODE=3)
compare "vol: set failure status" +0.05
SIDE_ENV=(FAKE_WPCTL_VOLUME=$'Volume: 0.50\n')
compare "vol: unsigned delta" 0.05
compare "vol: negative delta" -0.05
SIDE_ENV=()
FAKE_PATH=$(fake_path_without wpctl)
compare "vol: missing wpctl"
FAKE_PATH=$FAKES

# ── mpd_del_album ───────────────────────────────────────────────────────────

section "mpd_del_album"
begin mpd_del_album
compare "mpd_del_album: -h" -h
printf 'n\n' > "$WORK/stdin-n"
SIDE_ENV=(FAKE_MPC_ARTIST=$'The Artist\n' FAKE_MPC_FILE=$'The Artist/The Album/01.flac\n')
SIDE_STDIN=$WORK/stdin-n
compare "mpd_del_album: cancel"
printf 'y\n' > "$WORK/stdin-y"
SIDE_STDIN=$WORK/stdin-y
compare "mpd_del_album: accept"
SIDE_ENV=(FAKE_MPC_FILE=$'A/B/01.flac\n')
compare "mpd_del_album: artist argument" Somebody
SIDE_ENV=(FAKE_MPC_FILE=$'01.flac\n')
compare "mpd_del_album: no directory"
SIDE_ENV=(FAKE_MPC_FILE=$'Artist/Album/\n')
compare "mpd_del_album: trailing slash"
SIDE_ENV=(FAKE_MPC_FILE=$'a/b/c\n')
compare "mpd_del_album: nested"
SIDE_ENV=(FAKE_MPC_FILE=$'A/B/01.flac\n' FAKE_MPC_CODE=1)
compare "mpd_del_album: mpc failure"
SIDE_ENV=(FAKE_MPC_FILE=$'A/B/01.flac\n' FAKE_MV_CODE=1)
compare "mpd_del_album: mv failure"
SIDE_ENV=(FAKE_MPC_FILE=$'A/B/01.flac\n')
printf 'Y\n' > "$WORK/stdin-upper"
SIDE_STDIN=$WORK/stdin-upper
compare "mpd_del_album: uppercase Y"
printf '  y  \n' > "$WORK/stdin-spaces"
SIDE_STDIN=$WORK/stdin-spaces
compare "mpd_del_album: surrounding whitespace"
printf '\\y\n' > "$WORK/stdin-escaped"
SIDE_STDIN=$WORK/stdin-escaped
compare "mpd_del_album: escaped y"
printf 'y\\\n\n' > "$WORK/stdin-continuation"
SIDE_STDIN=$WORK/stdin-continuation
compare "mpd_del_album: backslash continuation"
SIDE_STDIN=/dev/null
compare "mpd_del_album: EOF"
FAKE_PATH=$(fake_path_without mv)
SIDE_ENV=(FAKE_MPC_FILE=$'A/B/01.flac\n')
SIDE_STDIN=$WORK/stdin-y
compare "mpd_del_album: missing mv"
FAKE_PATH=$FAKES
SIDE_STDIN=/dev/null

# ── sx ──────────────────────────────────────────────────────────────────────

section "sx"
begin sx
seed_sx() {
  local side root
  for side in o r; do
    root=$WORK/$side
    mkdir -p "$root/case/pictures/sub/deep" "$root/case/second"
    printf x > "$root/case/pictures/a.png"
    sleep 0.03
    printf x > "$root/case/pictures/b.jpg"
    sleep 0.03
    printf x > "$root/case/pictures/sub/c.jpeg"
    sleep 0.03
    printf x > "$root/case/pictures/sub/deep/d.GIF"
    printf x > "$root/case/pictures/notes.txt"
    printf x > "$root/case/pictures/noext"
    printf x > "$root/case/pictures/x.png.bak"
    sleep 0.03
    printf x > "$root/case/pictures/upper.PNG"
    printf x > "$root/case/second/one.png"
    ln -s a.png "$root/case/pictures/link.png"
    ln -s sub "$root/case/pictures/dirlink"
  done
}
seed_sx
compare "sx: --help" --help
compare "sx: -h" -h
compare "sx: default current directory"
compare "sx: sorted and filtered" pictures
compare "sx: multiple directories" pictures second
compare "sx: symlinks" pictures
compare "sx: missing directory" does-not-exist
SIDE_ENV=(FAKE_SWAYIMG_CODE=7)
compare "sx: swayimg status" pictures
SIDE_ENV=()
# A local ~/.local/bin/swayimg wins over PATH in both implementations.
for side in o r; do
  cat > "$WORK/$side/home/.local/bin/swayimg" << 'EOF'
#!/bin/sh
{
  printf 'local-swayimg\n'
  for a in "$@"; do printf 'ARG %s\n' "$a"; done
} >> "$FAKE_LOG_DIR/local-swayimg.argv"
: > "$FAKE_LOG_DIR/swayimg.list"
exit 0
EOF
  chmod +x "$WORK/$side/home/.local/bin/swayimg"
done
compare "sx: local swayimg preference" pictures
for side in o r; do rm -f "$WORK/$side/home/.local/bin/swayimg"; done
FAKE_PATH=$(fake_path_without swayimg)
compare "sx: missing swayimg"
FAKE_PATH=$FAKES

# ── sys-relief ──────────────────────────────────────────────────────────────

section "sys-relief"
begin sys-relief
SETTLE=0.6
compare "sys-relief: normal flow"
SIDE_ENV=(FAKE_SUDO_COMPACT_CODE=1)
compare "sys-relief: compact failure ignored"
SIDE_ENV=(FAKE_SUDO_DROP_CODE=1)
compare "sys-relief: drop failure aborts"
SIDE_ENV=(FAKE_SYNC_CODE=3)
compare "sys-relief: sync failure aborts"
SIDE_ENV=(FAKE_SUDO_RESTORE_CODE=1)
compare "sys-relief: restore failure"
SIDE_ENV=()
FAKE_PATH=$(fake_path_without notify-send)
compare "sys-relief: missing notify-send"
FAKE_PATH=$(fake_path_without sync)
compare "sys-relief: missing sync"
FAKE_PATH=$FAKES
SETTLE=0

# ── gh-issues-export ────────────────────────────────────────────────────────

section "gh-issues-export"
GH_ISSUE='[
  {
    "number": 7,
    "title": "A \"quoted\" title",
    "state": "open",
    "user": {"login": "alice"},
    "labels": [{"name": "bug"}, {"name": "help wanted"}],
    "assignees": [{"login": "bob"}],
    "milestone": {"title": "v1"},
    "created_at": "2026-01-02T03:04:05Z",
    "updated_at": "2026-01-03T04:05:06Z",
    "closed_at": null,
    "html_url": "https://github.com/o/r/issues/7",
    "comments": 0,
    "body": "Intro\n<!-- hidden -->\nOutro"
  }
]
'
GH_COMMENT_ISSUE='[
  {
    "number": 7,
    "title": "T",
    "state": "open",
    "user": {"login": "alice"},
    "labels": [],
    "assignees": [],
    "created_at": "x",
    "closed_at": null,
    "updated_at": "y",
    "html_url": "z",
    "comments": 1,
    "body": "Body"
  }
]'
GH_COMMENTS='[{"user":{"login":"carol"},"created_at":"2026-01-04T05:06:07Z","body":"Thanks!\n<!-- x -->\nDone"}]'
GH_RATE='{"resources":{"core":{"remaining":5000,"reset":0}}}'

begin gh-issues-export
compare "gh-issues-export: --help" --help
compare "gh-issues-export: -h" -h
compare "gh-issues-export: missing repository"
compare "gh-issues-export: unknown option" --wat
compare "gh-issues-export: invalid repository" owner
SIDE_ENV=(FAKE_GH_ISSUES='[]')
compare "gh-issues-export: no issues" --output out o/r
SIDE_ENV=(FAKE_GH_ISSUES="$GH_ISSUE")
compare "gh-issues-export: one issue" --output out o/r
SIDE_ENV=(FAKE_GH_ISSUES="$GH_COMMENT_ISSUE" FAKE_GH_COMMENTS="$GH_COMMENTS" FAKE_GH_RATE="$GH_RATE")
compare "gh-issues-export: comments" --output out o/r
SIDE_ENV=(FAKE_GH_ISSUES='[{"number":1,"title":"PR","pull_request":{"url":"x"}},{"number":2,"title":"Issue","state":"open","user":{"login":"a"},"labels":[],"assignees":[],"created_at":"x","updated_at":"y","html_url":"z","comments":0,"body":"B"}]')
compare "gh-issues-export: pull requests filtered" --output out o/r
SIDE_ENV=(FAKE_GH_ISSUES=$'[{"number":1,"title":"One","state":"open","user":{"login":"a"},"labels":[],"assignees":[],"created_at":"x","updated_at":"y","html_url":"z","comments":0,"body":"B"}]\n[{"number":2,"title":"Two","state":"open","user":{"login":"a"},"labels":[],"assignees":[],"created_at":"x","updated_at":"y","html_url":"z","comments":0,"body":"B"}]')
compare "gh-issues-export: concatenated pages" --output out o/r
SIDE_ENV=(FAKE_GH_ISSUES="$GH_ISSUE")
compare "gh-issues-export: state filter" --state closed --output out o/r
SIDE_ENV=(FAKE_GH_ISSUES_CODE=1)
compare "gh-issues-export: fetch failure" --output out o/r
SIDE_ENV=(FAKE_GH_ISSUES="$GH_COMMENT_ISSUE" FAKE_GH_COMMENTS_CODE=1 FAKE_GH_RATE="$GH_RATE")
compare "gh-issues-export: comment failure" --output out o/r
for side in o r; do printf 'not a directory\n' > "$WORK/$side/case/out-file"; done
SIDE_ENV=(FAKE_GH_ISSUES="$GH_ISSUE")
compare "gh-issues-export: write failure exits zero" --output out-file o/r
SIDE_ENV=(FAKE_GH_ISSUES="$GH_COMMENT_ISSUE" FAKE_GH_COMMENTS='[]' FAKE_GH_RATE='{"resources":{"core":{"remaining":10,"reset":9999999999}}}')
compare "gh-issues-export: low rate limit" --output out o/r
SIDE_ENV=(FAKE_GH_ISSUES='[]' FAKE_GH_AUTH_CODE=1)
compare "gh-issues-export: auth failure" --output out o/r
SIDE_ENV=(FAKE_GH_ISSUES='[]' FAKE_GH_REPO_CODE=1)
compare "gh-issues-export: repository failure" --output out o/r
SIDE_ENV=(FAKE_GH_ISSUES='[]')
compare "gh-issues-export: default output directory" o/r
# Incremental: seed the metadata on both sides first.
for side in o r; do
  mkdir -p "$WORK/$side/case/out"
  printf '%s\n' '{"last_export_iso":"2026-01-01T00:00:00Z"}' > "$WORK/$side/case/out/.export-meta.json"
done
compare "gh-issues-export: incremental" --output out o/r
for side in o r; do
  mkdir -p "$WORK/$side/case/out"
  printf '%s\n' '{"last_export_iso":"2026-01-01T00:00:00Z"}' > "$WORK/$side/case/out/.export-meta.json"
done
compare "gh-issues-export: full mode" --full --output out o/r
SIDE_ENV=()
FAKE_PATH=$(fake_path_without gh)
SIDE_ENV=(FAKE_GH_ISSUES='[]')
compare "gh-issues-export: missing gh" o/r
FAKE_PATH=$FAKES

# ── win-vm ──────────────────────────────────────────────────────────────────

section "win-vm"
seed_win_vm() {
  local side root
  for side in o r; do
    root=$WORK/$side
    mkdir -p "$root/case/fixtures"
    local name
    for name in OVMF_CODE.fd OVMF_VARS.fd win.iso virtio.iso disk.qcow2; do
      printf fixture > "$root/case/fixtures/$name"
    done
    mkdir -p "$root/xdg/config/win-vm"
    cat > "$root/xdg/config/win-vm/config.sh" << EOF
VM_NAME="testvm"
VM_OVMF_CODE="$root/case/fixtures/OVMF_CODE.fd"
VM_OVMF_VARS_TEMPLATE="$root/case/fixtures/OVMF_VARS.fd"
VM_WINDOWS_ISO="$root/case/fixtures/win.iso"
VM_VIRTIO_ISO="$root/case/fixtures/virtio.iso"
VM_VIRTIO_ISO_URL="https://example.invalid/virtio-win.iso"
VM_DISK_PATH="$root/case/fixtures/disk.qcow2"
EOF
  done
}

begin win-vm
# The original help is sed-based and needs a UTF-8 locale for the box-drawing
# separator; under LC_ALL=C it prints the rest of the script as well.
SIDE_ENV=(LANG=C.UTF-8 LC_ALL=C.UTF-8)
compare "win-vm: --help" --help
compare "win-vm: default help"
compare "win-vm: unknown command" bogus
SIDE_ENV=()
compare "win-vm: init" init
compare "win-vm: init existing" init

begin win-vm
seed_win_vm
compare "win-vm: check clean" check
SIDE_ENV=(FAKE_ID_GROUPS="neg wheel" FAKE_SYSTEMCTL_CODE=3 FAKE_VIRSH_NETINFO=$'Active: no\n' USER=neg)
for side in o r; do rm -f "$WORK/$side/bin-does-not-exist"; done
FAKE_PATH=$(fake_path_without swtpm)
compare "win-vm: check warnings" check
FAKE_PATH=$FAKES
SIDE_ENV=(FAKE_VIRSH_NETINFO=$'Active: no\n')
compare "win-vm: prepare starts network" prepare
SIDE_ENV=()
for side in o r; do
  mkdir -p "$WORK/$side/case/new"
  rm -f "$WORK/$side/case/new/disk.qcow2"
  root=$WORK/$side
  sed -i "\|^VM_DISK_PATH=|d" "$root/xdg/config/win-vm/config.sh"
  printf 'VM_DISK_PATH="%s/case/new/disk.qcow2"\n' "$root" >> "$root/xdg/config/win-vm/config.sh"
done
compare "win-vm: prepare creates disk" prepare
# Missing Windows ISO.
for side in o r; do
  root=$WORK/$side
  printf 'VM_WINDOWS_ISO="%s/case/missing.iso"\n' "$root" >> "$root/xdg/config/win-vm/config.sh"
done
compare "win-vm: prepare missing Windows ISO" prepare

begin win-vm
seed_win_vm
append_sides 'VM_NAME="vm1"'
append_sides 'VM_RAM_MB=8192'
append_sides 'VM_CPU_SOCKETS=1'
append_sides 'VM_CPU_CORES=2'
append_sides 'VM_CPU_THREADS=2'
append_sides 'VM_GPU_PCI_BDF="0000:03:00.0"'
append_sides 'VM_GPU_AUDIO_BDF="0000:03:00.1"'
append_sides 'VM_CPU_PIN_SET="0 1 2 3"'
append_sides 'VM_HUGEPAGES="yes"'
compare "win-vm: define" define
SIDE_ENV=(FAKE_VIRSH_DOMINFO_CODE=0)
compare "win-vm: define existing" define
SIDE_ENV=(FAKE_VIRSH_DOMINFO_CODE=0 FAKE_VIRSH_DOMSTATE=shut off)
compare "win-vm: start" start
SIDE_ENV=(FAKE_VIRSH_DOMINFO_CODE=0 FAKE_VIRSH_DOMSTATE=running)
compare "win-vm: start running" start
compare "win-vm: stop" stop
compare "win-vm: kill" kill
compare "win-vm: edit" edit
compare "win-vm: status defined" status
SIDE_ENV=(FAKE_VIRSH_DOMINFO_CODE=1)
compare "win-vm: status missing" status
SIDE_ENV=(FAKE_VIRSH_DOMINFO_CODE=0 FAKE_VIRSH_DOMSTATE=shut off)
compare "win-vm: undefine without tty" undefine
compare "win-vm: destroy-all without tty" destroy-all
compare "win-vm: eject-install real layout" eject-install
# Both configs point at one shared ISO so the synthetic cdrom row matches.
SHARED_WIN=$WORK/shared-win.iso
printf iso > "$SHARED_WIN"
for side in o r; do
  root=$WORK/$side
  printf 'VM_WINDOWS_ISO="%s"\n' "$SHARED_WIN" >> "$root/xdg/config/win-vm/config.sh"
done
SIDE_ENV=(FAKE_VIRSH_DOMINFO_CODE=0 FAKE_VIRSH_DOMSTATE=shut off FAKE_VIRSH_DOMBLLIST="cdrom cdrom sda $SHARED_WIN")
compare "win-vm: eject-install matching filter" eject-install
SIDE_ENV=(FAKE_VIRSH_DOMINFO_CODE=0 FAKE_VIRSH_DOMSTATE=shut off)
compare "win-vm: gpu-add" gpu-add
compare "win-vm: gpu-remove" gpu-remove
compare "win-vm: lg-enable" lg-enable
compare "win-vm: cpupin" cpupin
append_sides 'VM_HUGEPAGES="yes"'
compare "win-vm: hugepages" hugepages
compare "win-vm: usb-add stopped" usb-add 0951:16ae
SIDE_ENV=(FAKE_VIRSH_DOMINFO_CODE=0 FAKE_VIRSH_DOMSTATE=running)
compare "win-vm: usb-add live" usb-add 0951:16ae
compare "win-vm: usb-remove" usb-remove 0951:16ae
SIDE_ENV=(FAKE_VIRSH_DOMINFO_CODE=0 FAKE_VIRSH_DOMSTATE=shut off FAKE_VIRSH_DOMDISPLAY=$'spice://127.0.0.1:5900\n')
compare "win-vm: console spicy" console
if [ -e /dev/shm/looking-glass ]; then
  skip "win-vm: looking-glass missing (host has /dev/shm/looking-glass)"
else
  SIDE_ENV=(FAKE_VIRSH_DOMINFO_CODE=0)
  compare "win-vm: looking-glass missing" looking-glass
fi

# ── Summary ─────────────────────────────────────────────────────────────────

printf '\n%d checks, %d failed, %d skipped\n' "$CHECKS" "$FAILED" "$SKIPPED"
[ "$FAILED" -eq 0 ]
