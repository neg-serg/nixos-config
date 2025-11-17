#!/usr/bin/env zsh
# pl: fuzzy-pick and play videos (fzf/rofi -> mpv + vid-info)
# Usage:
#   pl [rofi|video|1st_level] [DIR]
#   pl cmd <playerctl-args>
#   pl vol {mute|unmute}


IFS=$'\n\t'

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

need() { command -v "$1" >/dev/null 2>&1 || { print -u2 "pl: missing $1"; :; }; }

mp() {
    local -a files
    files=("$@")
    if command -v vid-info >/dev/null 2>&1; then
        # Info for directories
        for f in "$@"; do
            if [[ -d "$f" ]]; then
                { find -- "$f" -maxdepth 1 -type f -print0 | xargs -0 -n10 -P 10 vid-info; } &
            fi
        done
        # Info for files
        {
            local -a only_files
            only_files=()
            for f in "$@"; do
                [[ -f "$f" ]] && only_files+=("$f")
            done
            if (( ${#only_files[@]} )); then
                printf '%s\0' "${only_files[@]}" | xargs -0 -n10 -P 10 vid-info
            fi
        } &
    fi
    mkdir -p -- "$HOME/tmp"
    local ipc="${XDG_CONFIG_HOME:-$HOME/.config}/mpv/socket"
    mpv --input-ipc-server="$ipc" --vo=gpu -- "$@" > "$HOME/tmp/mpv.log" 2>&1
}

find_candidates() {
    # find_candidates <dir> [maxdepth]
    local dir="$1"; local maxd="${2:-}"
    if command -v fd >/dev/null 2>&1; then
        local -a cmd
        cmd=(fd -t f --hidden --follow -E .git -E node_modules -E '*.srt' . "$dir")
        [[ -n "$maxd" ]] && cmd=(fd -t f --hidden --follow -E .git -E node_modules -E '*.srt' -d "$maxd" . "$dir")
        "${cmd[@]}"
    else
        local -a cmd
        cmd=(rg --files --hidden --follow -g '!{.git,node_modules}/*' -g '!*.srt' "$dir")
        [[ -n "$maxd" ]] && cmd=(rg --files --hidden --follow -g '!{.git,node_modules}/*' -g '!*.srt' --max-depth "$maxd" "$dir")
        "${cmd[@]}"
    fi
}

pl_fzf() {
    local dir="${1:-${XDG_VIDEOS_DIR:-$HOME/vid}}"
    dir="${~dir}"
    need fzf
    local sel
    sel=$(find_candidates "$dir" "$2" | fzf --multi --prompt '⟬vid⟭ ❯>' || true)
    [[ -z "${sel:-}" ]] && return 0
    print -r -- "$sel" | wl-copy || true
    # Build absolute paths
    local -a targets
    targets=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" = /* ]]; then
            targets+=("$line")
        else
            targets+=("$dir/$line")
        fi
    done <<< "$sel"
    (( ${#targets[@]} )) && mp "${targets[@]}"
}

pl_rofi() {
    local dir="${1:-${XDG_VIDEOS_DIR:-$HOME/vid}}"
    dir="${~dir}"
    local maxd="${2:-}"
    local list sel
    # Build candidate list (files)
    list=$(find_candidates "$dir" "$maxd")
    # Also include top-level subdirectories for quick selection
    local dirs
    if command -v fd >/dev/null 2>&1; then
        dirs=$(fd -td -d 1 . "$dir" 2>/dev/null | sed "s:^$dir/::" | sed '/^$/d')
    else
        dirs=$(find "$dir" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sed '/^$/d')
    fi
    # Decorate entries with icons and grey tails: duration • date
    local decorated
    decorated=$( {
        # Directories first (prefix icon and trailing slash)
        printf '%s\n' "$dirs" | while IFS= read -r d; do
            [ -z "$d" ] && continue
            # mtime date
            ddate=$(stat -c '%y' "$dir/$d" 2>/dev/null | awk '{print $1}' )
            # escape markup special chars in name
            d_esc=$(printf '%s' "$d" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
            printf ' %s/  <span foreground="#778899">[%s]</span>\n' "$d_esc" "${ddate:-}"
        done
        # Files with duration + date
        printf '%s\n' "$list" | while IFS= read -r f; do
            [ -z "$f" ] && continue
            # Normalize to relative (fd already prints relative; rg may print absolute)
            case "$f" in
                /*) rel="${f#"$dir/"}" ;;
                *)  rel="$f" ;;
            esac
            # escape markup special chars in name
            rel_esc=$(printf '%s' "$rel" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
            # duration (mm:ss or hh:mm:ss) via ffprobe if available
            dur=""
            if command -v ffprobe >/dev/null 2>&1; then
                secs=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 -- "$dir/$rel" 2>/dev/null | awk '{printf "%d\n", $1}' )
                if [ -n "${secs}" ] && [ "$secs" -gt 0 ] 2>/dev/null; then
                    if [ "$secs" -ge 3600 ]; then
                        dur=$(awk -v s="$secs" 'BEGIN{printf "%d:%02d:%02d\n", int(s/3600), int(s%3600/60), int(s%60)}')
                    else
                        dur=$(awk -v s="$secs" 'BEGIN{printf "%d:%02d\n", int(s/60), int(s%60)}')
                    fi
                fi
            fi
            fdate=$(stat -c '%y' "$dir/$rel" 2>/dev/null | awk '{print $1}')
            if [ -n "$dur" ]; then
                tail="[$dur • ${fdate:-}]"
            else
                tail="[${fdate:-}]"
            fi
            printf '%s  <span foreground="#778899">%s</span>\n' "$rel_esc" "$tail"
        done
    } )
    if [[ -z "$list" ]]; then
        return 0
    fi
    if (( ${#${(f)decorated}[@]} > 1 )); then
        sel=$(print -r -- "$decorated" | rofi -theme menu -p 'vid ❯>' -i -dmenu -markup-rows \
            -kb-accept-alt 'Alt+Return' -kb-custom-1 'Alt+1' -kb-custom-2 'Alt+2')
        rc=$?
    else
        sel="$decorated"; rc=0
    fi
    [[ -z "${sel:-}" ]] && return 0
    # Strip grey tail markup and recover path/relname
    sel="${sel%%  <span*}"
    # Remove directory icon and trailing slash
    sel="${sel# }"; sel="${sel%/}"
    # Absolute path
    if [[ "$sel" != /* ]]; then sel="$dir/$sel"; fi
    case "$rc" in
        10) print -r -- "$sel" | wl-copy ;;                              # Alt+1: copy path
        11) xdg-open "${sel%/*}" >/dev/null 2>&1 || true ;;               # Alt+2: open dir
        *)  print -r -- "$sel" | wl-copy || true; mp "$sel" ;;            # default: play
    esac
}

main() {
    local set_maxdepth=false
    local maxd=""
    local mode="fzf"
    local dir=""
    if [[ "${1:-}" == "rofi" ]]; then
        mode="rofi"; shift
    fi
    if [[ "${1:-}" == "video" ]]; then
        # File-browser view with dynamic dir and item count in mesg
        shift
        local fbdir="${1:-${XDG_VIDEOS_DIR:-$HOME/vid}/new}"
        fbdir="${~fbdir}"
        local items
        if command -v fd >/dev/null 2>&1; then
            items=$(fd -d 1 -t f . "$fbdir" 2>/dev/null | wc -l | tr -d ' ')
        else
            items=$(find "$fbdir" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
        fi
        local dir_label
        dir_label=${fbdir/#$HOME/~}
        rofi -modi file-browser-extended -show file-browser-extended -p 'vid ❯>' -markup-rows \
            -file-browser-dir "$fbdir" -file-browser-depth 1 \
            -file-browser-open-multi-key "kb-accept-alt" \
            -file-browser-open-custom-key "kb-custom-11" \
            -file-browser-hide-hidden-symbol "" \
            -file-browser-path-sep "/" -theme menu \
            -file-browser-cmd 'mpv --input-ipc-server=/tmp/mpvsocket --vo=gpu'
        return
    fi
    if [[ "${1:-}" == "1st_level" ]]; then
        set_maxdepth=true; shift
    fi
    dir="${1:-}"
    if [[ "$set_maxdepth" == true ]]; then maxd=1; fi
    if [[ "$mode" == rofi ]]; then
        pl_rofi "${dir:-}" "$maxd"
    else
        pl_fzf "${dir:-}" "$maxd"
    fi
}

case "${1:-}" in
    -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    cmd) shift; playerctl "$@" ;;
    vol)
        case "${2:-}" in
            mute) vset 0.0 || amixer -q set Master 0 mute ;;
            unmute) vset 1.0 || amixer -q set Master 65536 unmute ;;
        esac ;;
    *) main "$@" ;;
esac
