#!/usr/bin/env zsh
# swayimg-actions: move/copy/rotate/wallpaper for swayimg; dests limited to $XDG_PICTURES_DIR; before mv send prev_file via IPC to avoid end-of-list crash

IFS=$'\n\t'
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0
fi

# Some launchers sanitize PATH; fall back to a sane default so wl-copy/etc. stay reachable.
if [ -z "${PATH:-}" ]; then
  PATH="$HOME/.local/bin:$HOME/.local/state/nix/profile/bin:$HOME/.nix-profile/bin"
  PATH="$PATH:/etc/profiles/per-user/${USER:-${LOGNAME:-}}/bin:/run/current-system/sw/bin"
  PATH="$PATH:/run/wrappers/bin:/usr/bin:/bin"
  export PATH
  path=(${(s/:/)PATH})
else
  export PATH
fi

# Run heavy actions out-of-band so swayimg doesn't block; set SWAYIMG_ACTIONS_SYNC=1 to opt out.
if [ "${SWAYIMG_ACTIONS_SYNC:-0}" != 1 ] && [ -z "${SWAYIMG_ACTIONS_ASYNC_CHILD:-}" ]; then
  export SWAYIMG_ACTIONS_ASYNC_CHILD=1
  if command -v setsid >/dev/null 2>&1; then
    setsid -f -- "$0" "$@" &!
  else
    "$0" "$@" &!
  fi
  exit 0
fi

cache="${HOME}/tmp"
mkdir -p "${cache}"
ff="${cache}/swayimg.$$"
tmp_wall="${cache}/wall_swww.$$"
debug_log="${cache}/swayimg-actions.log"
debug_target="${SWAYIMG_ACTIONS_DEBUG:-}"
_debug() {
  [ -n "$debug_target" ] || return 0
  local ts msg line
  ts="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date 2>/dev/null || printf '%s' 'unknown-time')"
  msg="$*"
  [ -n "$msg" ] || msg="(empty)"
  line="$ts $msg"
  printf '%s\n' "$line" >> "$debug_log"
  if [ "$debug_target" = "stderr" ]; then
    printf 'swayimg-actions(debug): %s\n' "$line" >&2
  fi
}
swayimg_data="${XDG_DATA_HOME:-$HOME/.local/share}/swayimg"
mkdir -p "$swayimg_data"
last_file="${swayimg_data}/last"
trash="${HOME}/trash/1st-level/pic"
rofi_cmd='rofi -dmenu -sort -matching fuzzy -no-plugins -no-only-match -theme viewer -custom'
pics_dir_default="$HOME/Pictures"
pics_dir="${XDG_PICTURES_DIR:-$pics_dir_default}"
session_id="${SWAYIMG_SESSION_ID:-manual}"
playlist_file="${SWAYIMG_FILELIST:-${swayimg_data}/${session_id}.list}"
range_file="${SWAYIMG_RANGE_FILE:-${swayimg_data}/${session_id}.range}"
typeset -a playlist
typeset -gi range_idx

# ---- path guards -----------------------------------------------------------
# Never operate on files inside any VCS directory (.git, .hg, .svn, .bzr):
# - don't set wallpapers from there, don't move/copy/rotate from/to there.
_is_vcs_path() {
  local p
  p="${1%/}"
  case "$p" in
    */.git|*/.git/*|.git|.git/*) return 0 ;;
    */.hg|*/.hg/*|.hg|.hg/*) return 0 ;;
    */.svn|*/.svn/*|.svn|.svn/*) return 0 ;;
    */.bzr|*/.bzr/*|.bzr|.bzr/*) return 0 ;;
    *) return 1 ;;
  esac
}

_require_not_vcs() { # _require_not_vcs <path> <what>
  local p="$1" what="$2"
  if _is_vcs_path "$p"; then
    printf 'swayimg-actions: skip %s inside VCS dir: %s\n' "$what" "$p" >&2
    return 1
  fi
  return 0
}

# ---- session / range helpers -----------------------------------------------
_resolve_realpath() {
  local target="$1" out=""
  if command -v realpath >/dev/null 2>&1; then
    out="$(realpath "$target" 2>/dev/null || true)"
  fi
  if [ -z "$out" ] && command -v readlink >/dev/null 2>&1; then
    out="$(readlink -f "$target" 2>/dev/null || true)"
  fi
  [ -n "$out" ] && printf '%s\n' "$out" || printf '%s\n' "$target"
}

_range_warn() {
  announce_action "$1"
}

_range_load_playlist() {
  playlist=()
  [ -f "$playlist_file" ] || return 1
  playlist=("${(@f)$(<"$playlist_file")}")
  [ "${#playlist[@]}" -gt 0 ] || return 1
  return 0
}

_range_find_index() {
  local needle="$1" entry
  range_idx=0
  [ "${#playlist[@]}" -gt 0 ] || return 1
  local -i idx=1
  for entry in "${playlist[@]}"; do
    if [[ "$entry" == "$needle" ]]; then
      range_idx=$idx
      return 0
    fi
    (( idx++ ))
  done
  return 1
}

_range_stage_selection() {
  local file="$1" mark current
  if [ ! -f "$playlist_file" ]; then
    _range_warn "диапазон доступен только при запуске через sx"
    return 1
  fi
  if [ ! -f "$range_file" ]; then
    _range_warn "сначала поставь метку диапазона (Shift+m)"
    return 1
  fi
  mark="$(<"$range_file")"
  [ -n "$mark" ] || { _range_warn "метка пуста"; return 1; }
  _range_load_playlist || { _range_warn "не удалось загрузить список файлов"; return 1; }
  mark="$(_resolve_realpath "$mark")"
  current="$(_resolve_realpath "$file")"
  if ! _range_find_index "$mark"; then
    _range_warn "метка не найдена в активном списке"
    return 1
  fi
  local -i start_idx=$range_idx
  if ! _range_find_index "$current"; then
    _range_warn "текущий файл не найден в активном списке"
    return 1
  fi
  local -i end_idx=$range_idx
  local -i lower=$start_idx upper=$end_idx tmp
  if (( lower > upper )); then
    tmp=$lower
    lower=$upper
    upper=$tmp
  fi
  >"$ff"
  if (( lower > 0 && upper > 0 )); then
    printf '%s\n' "${playlist[$lower,$upper]}" >"$ff"
    return 0
  fi
  return 1
}

# ---- IPC helpers -----------------------------------------------------------
# Find swayimg IPC socket from env or runtime dir (best-effort)
_find_ipc_socket() {
  if [ -n "${SWAYIMG_IPC:-}" ] && [ -S "$SWAYIMG_IPC" ]; then
    printf '%s' "$SWAYIMG_IPC"
    return 0
  fi
  # Fallback: pick the newest socket that looks like swayimg-*.sock
  local rt="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  if [ -d "$rt" ]; then
    # shellcheck disable=SC2012
    local s
    s="$(ls -t "$rt"/swayimg-*.sock 2>/dev/null | head -n1 || true)"
    [ -n "$s" ] && [ -S "$s" ] && { printf '%s' "$s"; return 0; }
  fi
  return 1
}

_ipc_send() { # _ipc_send <command>
  local sock cmd
  cmd="$1"
  sock="$(_find_ipc_socket || true)"
  [ -n "$sock" ] || return 0
  if command -v socat >/dev/null 2>&1; then
    printf '%s\n' "$cmd" | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1 || true
  elif command -v ncat >/dev/null 2>&1; then
    printf '%s\n' "$cmd" | ncat -U "$sock" >/dev/null 2>&1 || true
  else
    return 0
  fi
}

# ---- status helpers --------------------------------------------------------
_pretty_path() {
  local p="${1:-}"
  if [ -z "$p" ]; then
    printf '%s' ""
    return 0
  fi
  if [ -n "${HOME:-}" ] && [[ "$p" == "$HOME"* ]]; then
    printf '~%s' "${p#$HOME}"
  else
    printf '%s' "$p"
  fi
}

announce_action() {
  local text="${1:-}"
  [ -n "$text" ] || return 0
  text="${text//$'\r'/ }"
  text="${text//$'\n'/ }"
  printf 'swayimg-actions: %s\n' "$text" >&2
  _ipc_send "status $text"
}

# ---- swww helpers -----------------------------------------------------------
ensure_swww() {
  # Start swww daemon if not running
  if swww query >/dev/null 2>&1; then
    return 0
  fi
  if ! command -v swww-daemon >/dev/null 2>&1; then
    printf 'swayimg-actions: swww-daemon not found on PATH; wallpapers unavailable\n' >&2
    return 1
  fi
  local -a daemon_cmd
  daemon_cmd=(swww-daemon)
  if [ -n "${SWWW_DAEMON_FLAGS:-}" ]; then
    daemon_cmd+=("${(z)SWWW_DAEMON_FLAGS}")
  fi
  if command -v setsid >/dev/null 2>&1; then
    setsid -f -- "${daemon_cmd[@]}" >/dev/null 2>&1 || true
  else
    "${daemon_cmd[@]}" >/dev/null 2>&1 &!
  fi
  sleep 0.1
}

# Serialize wallpaper changes across different callers (queue behavior)
_wl_lock_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wl.lock.d"
acquire_wl_lock() {
  local attempts=0
  while ! mkdir "$_wl_lock_dir" 2>/dev/null; do
    if [ -f "$_wl_lock_dir/pid" ]; then
      local pid
      pid="$(cat "$_wl_lock_dir/pid" 2>/dev/null || true)"
      if [ -n "${pid}" ] && ! kill -0 "$pid" 2>/dev/null; then
        rm -rf "$_wl_lock_dir" 2>/dev/null || true
        continue
      fi
    fi
    attempts=$(( attempts + 1 ))
    sleep 0.2
    [ $attempts -ge 300 ] && break
  done
  echo $$ >"$_wl_lock_dir/pid" 2>/dev/null || true
}
release_wl_lock() {
  [ -d "$_wl_lock_dir" ] && rm -rf "$_wl_lock_dir" 2>/dev/null || true
}

# Return maximum WxH among active outputs (fallback 1920x1080)
screen_wh() {
  local wh
  if command -v swaymsg >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    wh="$(swaymsg -t get_outputs -r 2>/dev/null \
      | jq -r '[.[] | select(.active and .current_mode != null)
                | {w:.current_mode.width|tonumber, h:.current_mode.height|tonumber, a:(.current_mode.width|tonumber)*(.current_mode.height|tonumber)}]
               | if length>0 then (max_by(.a) | "\(.w)x\(.h)") else empty end' 2>/dev/null || true)"
  fi
  [ -n "${wh:-}" ] && printf '%s\n' "$wh" || printf '1920x1080\n'
}

# Render image to tmp file based on mode for swww
# writes output path to $tmp_wall
render_for_mode() {
  local mode="$1" file="$2" wh
  if ! command -v convert >/dev/null 2>&1; then
    return 1
  fi
  wh="$(screen_wh)"
  rm -f "$tmp_wall" 2>/dev/null || true
  case "$mode" in
    cover|full|fill)
      # cover: crop to fill screen from center
      convert "$file" -resize "${wh}^" -gravity center -extent "$wh" "$tmp_wall" ;;
    center)
      # fit inside with borders, centered
      convert "$file" -resize "${wh}" -gravity center -background black -extent "$wh" "$tmp_wall" ;;
    tile)
      # make tiled canvas of exact screen size
      convert -size "$wh" tile:"$file" "$tmp_wall" ;;
    mono)
      convert "$file" -colors 2 "$tmp_wall" ;;
    retro)
      convert "$file" -colors 12 "$tmp_wall" ;;
    *)
      # default to cover
      convert "$file" -resize "${wh}^" -gravity center -extent "$wh" "$tmp_wall"
      ;;
  esac
}

# ---- helpers ---------------------------------------------------------------
rotate() { # modifies file in-place
  local angle="$1"
  shift
  local -i rotated=0
  while read -r file; do
    _require_not_vcs "$file" rotate || continue
    mogrify -rotate "$angle" "$file"
    (( rotated++ ))
  done
  if (( rotated > 0 )); then
    local suffix="s"
    (( rotated == 1 )) && suffix=""
    announce_action "rotated ${rotated} file${suffix} by ${angle}°"
  fi
}

choose_dest() {
  # Fuzzy-pick a destination dir using zoxide history, limited to XDG_PICTURES_DIR
  local prompt="$1"
  local entries

  entries="$(
    {
      command -v zoxide >/dev/null 2>&1 && zoxide query -l 2>/dev/null || true
    } \
    | awk -v pic="$pics_dir" 'index($0, pic) == 1' \
    | awk '!/(^|\/)\.(git|hg|svn|bzr)(\/|$)/' \
    | sed "s:^$HOME:~:" \
    | awk 'NF' \
    | sort -u
  )"

  if [ -z "$entries" ]; then
    entries="$(
      {
        printf '%s\n' "$pics_dir"
        if command -v fd >/dev/null 2>&1; then
          # Exclude VCS dirs from candidates
          fd -td -d 3 . "$pics_dir" -E .git -E .hg -E .svn -E .bzr 2>/dev/null
        else
          # Prune VCS dirs when listing
          find "$pics_dir" -maxdepth 3 \( -type d \( -name .git -o -name .hg -o -name .svn -o -name .bzr \) -prune \) -o -type d -print 2>/dev/null
        fi
      } \
      | sed "s:^$HOME:~:" \
      | awk 'NF' \
      | sort -u
    )"
  fi

  printf '%s\n' "$entries" \
    | sh -c "$rofi_cmd -p \"$prompt ❯>\"" \
    | sed "s:^~:$HOME:"
}

_proc_apply_list() { # _proc_apply_list <cmd> [dest]
  local cmd="$1" dest="${2:-}"
  local -i moved=0

  if [ -z "${dest}" ]; then
    dest="$(choose_dest "$cmd" || true)"
  fi
  [ -n "${dest}" ] || return 0
  if _is_vcs_path "$dest"; then
    printf 'swayimg-actions: refusing to %s to VCS dir: %s\n' "$cmd" "$dest" >&2
    return 0
  fi
  if [ -d "$dest" ]; then
    if [ "$cmd" = "mv" ]; then
      _ipc_send "prev_file"
    fi
    local line
    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] || continue
      if _is_vcs_path "$line"; then
        printf 'swayimg-actions: skip %s source in VCS dir: %s\n' "$cmd" "$line" >&2
        continue
      fi
      "$cmd" "$(realpath "$line")" "$dest"
      (( moved++ ))
    done <"$ff"
    if (( moved > 0 )); then
      command -v zoxide >/dev/null 2>&1 && zoxide add "$dest" || true
      {
        printf '%s\n' "$cmd"
        printf '%s\n' "$dest"
      } >"$last_file"
      local verb dest_pretty suffix="s"
      case "$cmd" in
        mv) verb="moved" ;;
        cp) verb="copied" ;;
        *) verb="$cmd" ;;
      esac
      (( moved == 1 )) && suffix=""
      dest_pretty="$(_pretty_path "$dest")"
      announce_action "${verb} ${moved} file${suffix} → ${dest_pretty}"
    fi
  fi
}

proc() { # mv/cp with remembered last dest
  cmd="$1"; file="$2"; dest="${3:-}"
  printf '%s\n' "$file" | tee "$ff" >/dev/null
  if _is_vcs_path "$file"; then
    printf 'swayimg-actions: refusing to %s from VCS dir: %s\n' "$cmd" "$file" >&2
    return 0
  fi
  _proc_apply_list "$cmd" "$dest"
}

repeat_action() { # repeat last mv/cp to same dir
  local file="$1" cmd="" dest="" last=""
  [ -f "$last_file" ] || exit 0
  {
    IFS= read -r cmd || true
    IFS= read -r dest || true
  } <"$last_file"
  if [ -z "$cmd" ] || [ -z "$dest" ]; then
    last="$(cat "$last_file")"
    cmd="${last%% *}"
    dest="${last#* }"
  fi
  [ -n "$cmd" ] && [ -n "$dest" ] || exit 0
  if [ "$cmd" = "mv" ] || [ "$cmd" = "cp" ]; then
    "$cmd" "$file" "$dest"
    local base dest_pretty
    base="$(basename "$file")"
    dest_pretty="$(_pretty_path "$dest")"
    announce_action "repeat ${cmd} ${base} → ${dest_pretty}"
  fi
}

range_mark() {
  local file="$1" current
  if ! _range_load_playlist; then
    _range_warn "не удалось загрузить список файлов (запусти через sx)"
    return 0
  fi
  current="$(_resolve_realpath "$file")"
  if ! _range_find_index "$current"; then
    _range_warn "файл не найден в активном списке — диапазон недоступен"
    return 0
  fi
  printf '%s\n' "$current" >| "$range_file"
  local -i total=${#playlist[@]}
  local -i idx=$range_idx
  local base
  base="$(basename "$current")"
  announce_action "range anchor ${idx}/${total}: ${base}"
}

range_clear() {
  rm -f "$range_file"
  announce_action "range anchor cleared"
}

range_trash() {
  local file="$1"
  if _range_stage_selection "$file"; then
    _proc_apply_list "mv" "$trash"
    rm -f "$range_file"
  fi
}

range_mv() {
  local file="$1"
  if _range_stage_selection "$file"; then
    _proc_apply_list "mv"
  fi
}

range_cp() {
  local file="$1"
  if _range_stage_selection "$file"; then
    _proc_apply_list "cp"
  fi
}

copy_name() { # copy absolute path to clipboard
  local file="$1" abs_path pretty rc hint
  _debug "copy_name start file='${file}'"
  if [ -z "$file" ]; then
    _debug "copy_name: empty file argument"
    announce_action "copyname failed (empty file)"
    return 1
  fi
  if ! _require_not_vcs "$file" copy; then
    _debug "copy_name: skipped due to VCS guard (file=${file})"
    return 0
  fi
  if ! command -v wl-copy >/dev/null 2>&1; then
    _debug "copy_name: wl-copy not found; PATH=${PATH}"
    announce_action "copyname failed (wl-copy missing)"
    return 1
  fi
  abs_path="$(realpath "$file" 2>/dev/null || true)"
  if [ -z "$abs_path" ]; then
    _debug "copy_name: realpath failed, falling back to original path"
    abs_path="$file"
  fi
  if ! printf '%s\n' "$abs_path" | wl-copy; then
    rc=$?
    _debug "copy_name: wl-copy rc=${rc} WAYLAND_DISPLAY='${WAYLAND_DISPLAY:-}' XDG_RUNTIME_DIR='${XDG_RUNTIME_DIR:-}'"
    hint="copyname failed (wl-copy rc ${rc})"
    if [ -n "$debug_target" ] && [ "$debug_target" != "stderr" ]; then
      hint="${hint}; see ${debug_log}"
    fi
    announce_action "$hint"
    return $rc
  fi
  _debug "copy_name: wl-copy ok path='${abs_path}'"
  if command -v pic-notify >/dev/null 2>&1; then
    pic-notify "$file" || true
  fi
  pretty="$(_pretty_path "$abs_path")"
  announce_action "copied path → clipboard (${pretty})"
}

wall() { # wall <mode> <file> via swww
  local mode="$1" file="$2"
  # Never read or set wallpapers from VCS paths
  _require_not_vcs "$file" wallpaper || return 0
  ensure_swww
  render_for_mode "$mode" "$file" || return 0
  # Allow user to override transition opts via $SWWW_FLAGS
  acquire_wl_lock
  swww img "${SWWW_IMAGE_OVERRIDE:-$tmp_wall}" ${SWWW_FLAGS:-} >/dev/null 2>&1 || true
  release_wl_lock
  echo "$file" >> "${XDG_DATA_HOME:-$HOME/.local/share}/wl/wallpaper.list" 2>/dev/null || true
  local pretty
  pretty="$(_pretty_path "$file")"
  announce_action "wallpaper (${mode}) ← ${pretty}"
}

finish() { rm -f "$ff" "$tmp_wall" 2>/dev/null || true; }
trap finish EXIT

# ---- dispatch --------------------------------------------------------------
action="${1:-}"; file="${2:-}"

case "$action" in
  rotate-left) printf '%s\n' "$file" | rotate 270 ;;
  rotate-right) printf '%s\n' "$file" | rotate 90 ;;
  rotate-180) printf '%s\n' "$file" | rotate 180 ;;
  rotate-ccw) printf '%s\n' "$file" | rotate -90 ;;
  copyname) copy_name "$file" ;;
  repeat) repeat_action "$file" ;;
  range-mark) range_mark "$file" ;;
  range-clear) range_clear "${file:-}" ;;
  range-trash) range_trash "$file" ;;
  range-mv) range_mv "$file" ;;
  range-cp) range_cp "$file" ;;
  mv) proc mv "$file" "${3:-}" ;;
  cp) proc cp "$file" "${3:-}" ;;
  wall-mono) wall mono "$file" ;;
  wall-fill) wall fill "$file" ;;
  wall-full) wall full "$file" ;;
  wall-tile) wall tile "$file" ;;
  wall-center) wall center "$file" ;;
  wall-cover) wall cover "$file" ;;
  *) echo "Unknown action: $action" >&2; exit 2 ;;
esac
