#!/usr/bin/env bash
set -euo pipefail
uid="$(id -u)" # Unique socket path for this instance
rt="$XDG_RUNTIME_DIR"
[ -n "$rt" ] || rt="/run/user/$uid"
sock="$rt/swayimg-$PPID-$$-$RANDOM.sock"
session_id="$(basename "$sock" .sock)"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/swayimg"
playlist_file="$data_dir/${session_id}.list"
range_file="$data_dir/${session_id}.range"
mkdir -p "$data_dir"
# Export socket path and session metadata for helper scripts
export SWAYIMG_IPC="$sock"
export SWAYIMG_SESSION_ID="$session_id"
export SWAYIMG_FILELIST="$playlist_file"
export SWAYIMG_RANGE_FILE="$range_file"
# Pre-filter arguments to avoid VCS dirs (.git, .hg, .svn, .bzr)
is_vcs_path() {
  case "${1%/}" in
    */.git | */.git/* | .git | .git/*) return 0 ;;
    */.hg | */.hg/* | .hg | .hg/*) return 0 ;;
    */.svn | */.svn/* | .svn | .svn/*) return 0 ;;
    */.bzr | */.bzr/* | .bzr | .bzr/*) return 0 ;;
    *) return 1 ;;
  esac
}

out_args=()
for a in "$@"; do
  if [ -e "$a" ]; then
    # Skip any explicit VCS paths
    if is_vcs_path "$a"; then
      continue
    fi
    if [ -d "$a" ]; then
      # Expand directory to files, pruning VCS dirs
      while IFS= read -r -d '' f; do
        out_args+=("$f")
      done < <(find "$a" \( -type d \( -name .git -o -name .hg -o -name .svn -o -name .bzr \) -prune \) -o -type f -print0)
    else
      out_args+=("$a")
    fi
  else
    out_args+=("$a")
  fi
done

# Persist the expanded playlist for helper scripts (one realpath per line)
> "$playlist_file"
if [ "${#out_args[@]}" -gt 0 ]; then
  for arg in "${out_args[@]}"; do
    if [ -e "$arg" ]; then
      realpath "$arg" 2> /dev/null || true
    fi
  done | sed '/^[[:space:]]*$/d' >> "$playlist_file"
fi

# Start swayimg with IPC enabled
"@SWAYIMG_BIN@" --ipc="$sock" "${out_args[@]}" &
pid=$!
i=0
while :; do
  if ! kill -0 "$pid" 2> /dev/null; then break; fi
  [ -S "$sock" ] && break
  i=$((i + 1))
  [ "$i" -ge 40 ] && break
  sleep 0.025
done # Wait until the socket appears or process exits (max ~1s)
# Send on-start action(s) if socket is ready
if [ -S "$sock" ]; then
  action="$(printenv SWAYIMG_ONSTART_ACTION 2> /dev/null || true)"
  [ -n "$action" ] || action="first_file"
  # Send each action on its own line; keep spaces intact
  printf '%s' "$action" \
    | tr ';' '\n' \
    | sed '/^[[:space:]]*$/d' \
    | "@SOCAT_BIN@" - "UNIX-CONNECT:$sock" > /dev/null 2>&1 || true
fi
wait "$pid" # Forward exit code
rc=$?
if [ -S "$sock" ]; then
  rm -f "$sock"
fi # Best-effort cleanup
rm -f "$playlist_file" "$range_file" 2> /dev/null || true
exit $rc
