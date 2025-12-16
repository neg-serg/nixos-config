{ lib,
  config,
  pkgs,
  ... }: with lib;
  mkIf (config.features.gui.enable or false) (lib.mkMerge [
    {
      home.file = let
        # Python library paths for special scripts
        sp = pkgs.python3.sitePackages;
        libpp = "${pkgs.neg.pretty_printer}/${sp}";
        libcolored = "${pkgs.python3Packages.colored}/${sp}";

        # --- Content of scripts from packages/local-bin/bin ---
        anyText = ''
          # find_candidates <dir> [maxdepth]
          local dir="''$1"; local maxd="''${2:-}"
          if command -v fd >/dev/null 2>&1; then
              local -a cmd
              cmd=(fd -t f --hidden --follow -E .git -E node_modules -E '*.srt' . "''$dir")
              [[ -n "''$maxd" ]] && cmd=(fd -t f --hidden --follow -E .git -E node_modules -E '*.srt' -d "''$maxd" . "''$dir")
              "''${cmd[@]}"
          else
              local -a cmd
              cmd=(rg --files --hidden --follow -g '!{.git,node_modules}/*' -g '!*.srt' "''$dir")
              [[ -n "''$maxd" ]] && cmd=(rg --files --hidden --follow -g '!{.git,node_modules}/*' -g '!*.srt' --max-depth "''$maxd" "''$dir")
              "''${cmd[@]}"
          fi
          }

          pl_fzf() {
              local dir="''${1:-''${XDG_VIDEOS_DIR:-''$HOME/vid}}"
              dir="''${~dir}"
              need fzf
              local sel
              sel=$(find_candidates "''$dir" "''$2" | fzf --multi --prompt '⟬vid⟭ ❯>' || true)
              [[ -z "''${sel:-}" ]] && return 0
              print -r -- "''$sel" | wl-copy || true
              # Build absolute paths
              local -a targets
              targets=()
              while IFS= read -r line; do
                  [[ -z "''$line" ]] && continue
                  if [[ "''$line" = /* ]]; then
                      targets+=("''$line")
                  else
                      targets+=("''$dir/''$line")
                  fi
              done <<< "''$sel"
              (( ''${#targets[@]} )) && mp "''${targets[@]}"
          }

          pl_rofi() {
              local dir="''${1:-''${XDG_VIDEOS_DIR:-''$HOME/vid}}"
              dir="''${~dir}"
              local maxd="''${2:-}"
              local list sel
              list=$(find_candidates "''$dir" "''$maxd")
              if [[ -z "''$list" ]]; then
                  return 0
              fi
              if (( ''${#''${(f)list}[@]} > 1 )); then
                  sel=$(print -r -- "''$list" | rofi -theme clip -p '⟬vid⟭ ❯>' -i -dmenu)
              else
                  sel="''$list"
              fi
              [[ -z "''${sel:-}" ]] && return 0
              print -r -- "''$sel" | wl-copy || true
              # Absolute path
              if [[ "''$sel" != /* ]]; then
                  sel="''$dir/''$sel"
              fi
              mp "''$sel"
          }

          main() {
              local set_maxdepth=false
              local maxd=""
              local mode="fzf"
              local dir=""
              if [[ "''${1:-}" == "rofi" ]]; then
                  mode="rofi"; shift
              fi
              if [[ "''${1:-}" == "video" ]]; then
                  # Keep legacy rofi file-browser path
                  shift
                  rofi -modi file-browser-extended -show file-browser-extended \
                      -file-browser-dir "~/vid/new" -file-browser-depth 1 \
                      -file-browser-open-multi-key "kb-accept-alt" \
                      -file-browser-open-custom-key "kb-custom-11" \
                      -file-browser-hide-hidden-symbol "" \
                      -file-browser-path-sep "/" -theme clip \
                      -file-browser-cmd 'mpv --input-ipc-server=/tmp/mpvsocket --vo=gpu'
                  return
              fi
              if [[ "''${1:-}" == "1st_level" ]]; then
                  set_maxdepth=true; shift
              fi
              dir="''${1:-}"
              if [[ "''$set_maxdepth" == true ]]; then maxd=1; fi
              if [[ "''$mode" == rofi ]]; then
                  pl_rofi "''${dir:-}" "''$maxd"
              else
                  pl_fzf "''${dir:-}" "''$maxd"
              fi
          }

          case "''${1:-}" in
              -h|--help) sed -n '2,6p' "''$0" | sed 's/^# {0,1}//'; exit 0 ;; 
              cmd) shift; playerctl "''$@" ;; 
              vol)
                  case "''${2:-}" in
                      mute) vset 0.0 || amixer -q set Master 0 mute ;; 
                      unmute) vset 1.0 || amixer -q set Master 65536 unmute ;; 
                  esac ;; 
              *) main "''$@" ;; 
          esac
        '';

        pngoptimText = ''
          #!/bin/sh
          # pngoptim: optimize a PNG file with optipng/advpng/advdef
          # Usage: pngoptim FILE.png


          IFS=''
          ''

          usage() { printf "Usage: pngoptim FILE.png\n" >&2; exit 1; }
          need() { command -v "$1" >/dev/null 2>&1 || { printf 'pngoptim: missing %s\n' "$1" >&2; :; }; }

          case "${1:-}" in
            -h|--help|help|\?) usage ;; 
          esac
          [ -n "${1:-}" ] || usage
          [ -f "$1" ] || { printf 'pngoptim: no such file: %s\n' "$1" >&2; exit 1; }

          file="$1"
          case "$file" in
            *.png|*.PNG) :;; 
            *) printf 'pngoptim: not a PNG: %s\n' "$file" >&2; exit 1;; 
          esac

          need optipng
          optipng -o7 -- "$file"

          # Optional extra compression if tools are available
          if command -v advpng >/dev/null 2>&1; then
            advpng -z4 -- "$file" || true
          fi
          if command -v advdef >/dev/null 2>&1; then
            advdef -z4 -- "$file" || true
          fi
        '';

        pyprclientText = ''
          #!/bin/sh
          # pypr-client: send JSON-RPC to pyprland socket
          # Usage: pypr-client '{"cmd": "..."}'
          if [ -z "${1:-}" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
            echo "Usage: pypr-client '{\"cmd\": \"...\"}'" >&2
            exit 1
          fi
          socat - "UNIX-CONNECT:${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.pyprland.sock" <<< "$@"
        '';

        qeText = ''
          #!/usr/bin/env bash
          set -euo pipefail

          # qe: print the most recently modified subdirectory of the given directory.
          # Semantics are similar to the original zsh glob:
          #   ^.git*(/om[1]D)
          # i.e.:
          #   - look only at direct children (depth 1)
          #   - pick directories (including dot-dirs), excluding .git*
          #   - choose the one with the newest mtime
          #
          # Usage:
          #   qe            # last modified subdir of $PWD
          #   qe /path/dir  # last modified subdir of the given directory

          start="${1:-.}"

          # Move to the starting directory; on failure just print it and exit.
          if ! cd "$start" 2>/dev/null; then
            printf '%s\n' "$start"
            exit 0
          fi

          # Find immediate subdirectories (excluding .git*), sorted by mtime (newest first).
          # Requires GNU find (available on NixOS via coreutils/findutils).
          latest="$(
            find . -mindepth 1 -maxdepth 1 -type d ! -name '.git*' -printf '%T@ %P\n' 2>/dev/null \
              | sort -nr \
              | head -n1 \
              | cut -d' ' -f2-
          )"

          if [ -n "${latest:-}" ]; then
            # Print an absolute path for robustness.
            cd "$latest" 2>/dev/null || {
              # If cd fails for some reason, fall back to echoing the relative name.
              printf '%s\n' "$latest"
              exit 0
            }
            pwd
          else
            # No subdirectories found; fall back to the starting directory.
            pwd
          fi
        '';

        qrText = ''
          #!/bin/sh
          # qr: quick QR and screenshot helper
          # Usage:
          #   qr gen          # generate QR from current selection to ~/tmp/qrcode.png
          #   qr select       # select region → clipboard (PNG) + notify
          #   qr qr           # select region → scan QR → copy result + notify
          #   qr              # screenshot entire desktop → clipboard (PNG) + notify
          #   qr -h|--help    # this help


          IFS=''
          ''

          need() { command -v "$1" >/dev/null 2>&1 || { printf 'qr: missing %s\n' "$1" >&2; :; }; }
          need grim
          need slurp
          need wl-copy

          maimselect() { grim -g "$(slurp)" -; }
          clip() { # usage: clip [-t mimetype] (reads from stdin)
            mimetype="${1:-}"
            if [ "${1:-}" = "-t" ] || [ "${1:-}" = "--type" ]; then shift; mimetype="${1:-}"; shift || true; fi
            if [ -n "$mimetype" ]; then wl-copy --type "$mimetype"; else wl-copy; fi
          }

          case "${1:-}" in
              -h|--help) sed -n '2,12p' "$0" | sed 's/^# {0,1}//'; exit 0 ;; 
              gen) need qrencode; mkdir -p "$HOME/tmp"; qrencode -l H -d 75 -s 10 -o - "$(wl-paste)" > "$HOME/tmp/qrcode.png" ;; 
              # select a region to screenshot (or click to screenshot window)
              select) maimselect | clip -t image/png; dunstify "Screenshot" "Screenshot taken" ;; 
              # scan a QR code
              qr) 
                  need zbarimg; tmp_file=$(mktemp -t maimscript-XXXXXX)
                  if ! grim -g "$(slurp)" "$tmp_file"; then rm -f "$tmp_file"; exit 1; fi
                  scanresult=$(zbarimg --quiet --raw "$tmp_file" | tr -d '\n' || true)
                  if [ -z "$scanresult" ]; then
                      if command -v dunstify >/dev/null 2>&1; then dunstify "Screenshot" "No scan data found"; fi
                  else
                      echo "$scanresult" | clip
                      if command -v convert >/dev/null 2>&1; then
                          convert "$tmp_file" -resize 75x75 "$tmp_file"
                      fi
                      if command -v dunstify >/dev/null 2>&1; then dunstify -i "$tmp_file" "QR" "$scanresult\n(copied to clipboard)"; fi
                  fi
                  rm -f "$tmp_file"
                  ;; 
              # screenshot the entire desktop
              *) 
                  grim - | clip -t image/png
                  if command -v dunstify >/dev/null 2>&1; then dunstify "Screenshot" "Screenshot taken"; fi
                  ;; 
          esac
        '';

        readDocumentsText = ''
          #!/usr/bin/env zsh
          # read_documents: pick and open a document from ~/dw (rofi -> zathura)
          # Usage: read_documents [extra rofi args]

          IFS=$'\n\t'
          if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
            sed -n '2,3p' "$0" | sed 's/^# {0,1}//'; exit 0
          fi

          command -v rofi >/dev/null 2>&1 || { print -u2 'read_documents: rofi not found'; :; }
          command -v fd >/dev/null 2>&1 || { print -u2 'read_documents: fd not found'; :; }
          command -v zathura >/dev/null 2>&1 || { print -u2 'read_documents: zathura not found'; :; }

          fd . ~/dw/ -d 1 -t f -0 -e pdf -e djvu -e epub \
            | xargs -0 -n1 \
            | rofi -auto-select -modi file-browser-extended -show file-browser-extended \
                -file-browser-dir "~/dw" -file-browser-depth 1 \
                -file-browser-open-multi-key "kb-accept-alt" \
                -file-browser-open-custom-key "kb-custom-11" \
                -file-browser-hide-hidden-symbol "" \
                -file-browser-only-files \
                -file-browser-stdin \
                -file-browser-path-sep "/" -theme clip.rasi \
                -file-browser-cmd 'zathura' "$@"
        '';

        screenrecText = ''
          #!/usr/bin/env bash
          # Toggle screen recording with wf-recorder
          # Usage: screenrec [area|screen]

          set -euo pipefail

          RECORDINGS_DIR="${HOME}/vid/recordings"
          PIDFILE="/tmp/wf-recorder-${USER}.pid"
          MODE="${1:-screen}"

          mkdir -p "$RECORDINGS_DIR"

          is_recording() {
              [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
          }

          stop_recording() {
              if is_recording; then
                  kill -INT "$(cat "$PIDFILE")" 2>/dev/null || true
                  rm -f "$PIDFILE"
                  notify-send -u low "Screen Recording" "Recording stopped"
                  exit 0
              fi
          }

          start_recording() {
              local filename="$RECORDINGS_DIR/rec-$(date '+%Y%m%d-%H.%M.%S').mp4"
              local geometry=""

              if [ "$MODE" = "area" ]; then
                  geometry=$(slurp -d 2>/dev/null) || exit 0
                  if [ -z "$geometry" ]; then
                      exit 0
                  fi
              fi

              notify-send -u low "Screen Recording" "Recording started..."

              if [ -n "$geometry" ]; then
                  wf-recorder -g "$geometry" -c libx264rgb -r 60 -p crf=20 -p preset=superfast -f "$filename" &
              else
                  wf-recorder -c libx264rgb -r 60 -p crf=20 -p preset=superfast -f "$filename" &
              fi

              echo $! > "$PIDFILE"
          }

          # Toggle: if recording, stop; otherwise start
          if is_recording; then
              stop_recording
          else
              start_recording
          fi
        '';

        screenshotText = ''
          #!/bin/sh

          IFS=''
          ''
          show_help() {
            cat <<'EOF'
          Usage: screenshot [-r|-c|-d|-m|-o]
            (no args)  Full screen capture to ~/pic/shots
            -r         Rectangular selection (interactive)
            -c         Current window
            -d         Delayed shot (5s)
            -m         Show menu (rofi)
            -o         OCR region to clipboard (tesseract)
            -h, --help Show this help
          EOF
          }

          scr_dir=$HOME/pic/shots
          mkdir -p -- "$scr_dir"
          filename="screenshot-$(date +%Y-%m-%d_%H-%M-%S).png"
          summary_="$scr_dir/$filename"

          shot() {
            # Fullscreen screenshot via grim
            grim "$summary_" && ~/bin/pic-notify "$summary_"
          }
          select_region() {
            # Region selection via slurp
            grim -g "$(slurp)" "$summary_" && ~/bin/pic-notify "$summary_"
          }
          current_window() {
            # Try Hyprland active window, fall back to selection
            if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
              geo=$(hyprctl -j activewindow | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"') || geo=""
              if [ -n "$geo" ]; then
                grim -g "$geo" "$summary_" && ~/bin/pic-notify "$summary_" && return 0
              fi
            fi
            Select "$@"
          }
          delay() { sleep 5; shot "$@"; }
          full() { shot "$@"; }

          menu() {
              sel=$(printf '%s\n' \
                  "Full screen" \
                  "Rectangular selection" \
                  "Current window" \
                  "Delayed (5s)" \
                  | rofi -dmenu -theme clip -p '⟬shot⟭ ❯>' || true)
              case "$sel" in
                  "Full screen") full "$@" ;; 
                  "Rectangular selection") select_region "$@" ;; 
                  "Current window") current_window "$@" ;; 
                  "Delayed (5s)") delay "$@" ;; 
                  *) : ;; 
              esac
          }

          ocr() {
            command -v tesseract >/dev/null 2>&1 || { printf 'screenshot: missing tesseract\n' >&2; :; }
            grim -g "$(slurp)" - \
              | tesseract --dpi 96 -l eng - - \
              | wl-copy --type text/plain
            command -v notify-send >/dev/null 2>&1 && notify-send -i ebook-reader "OCR" "Saved to clipboard" || true
          }

          case "${1:-}" in
              -r) select_region "$@";;
              -c) current_window "$@";;
              -d) delay "$@";;
              -m) menu "$@";;
              -o) ocr "$@" ;; # thx to vincentbernat
              --help) show_help;; 
              -h) show_help;; 
              *) full "$@";;
          esac
        '';

        shotOptimizerText = ''
          #!/bin/sh
          # shot-optimizer: convert new BMP screenshots to PNG and remove BMP
          # Usage: shot-optimizer
          #   Watches ~/pic/shots for new .bmp files, converts to .png and deletes .bmp

          IFS=''
          ''
          if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
            sed -n '2,4p' "$0" | sed 's/^# {0,1}//'; exit 0
          fi

          need() { command -v "$1" >/dev/null 2>&1 || { printf 'shot-optimizer: missing %s\n' "$1" >&2; :; }; }
          need inotifywait
          need convert

          shots_dir="${HOME}/pic/shots"
          mkdir -p -- "$shots_dir"

          # Monitor only BMP creations/close_write, handle per-file to avoid rescans
          inotifywait -q -m -e close_write -e create --format '%w%f' "$shots_dir" \
            | while IFS= read -r path; do
                  case "$path" in
                      *.bmp|*.BMP) 
                          png="${path%.*}.png"
                          if convert -quality 10 -- "$path" "$png"; then
                              rm -f -- "$path"
                          fi
                          ;; 
                      *) :;; 
                  esac
              done
        '';

        swayimgActionsText = ''
          #!/usr/bin/env zsh
          # swayimg-actions: move/copy/rotate/wallpaper for swayimg; dests limited to $XDG_PICTURES_DIR; before mv send prev_file via IPC to avoid end-of-list crash

          IFS=$'\n\t'
          if [[ "$1" == "-h" || "$1" == "--help" ]]; then
            sed -n '2,7p' "$0" | sed 's/^# {0,1}//'
            exit 0
          fi

          cache="${HOME}/tmp"
          mkdir -p "${cache}"
          ff="${cache}/swayimg.$$"
          tmp_wall="${cache}/wall_swww.$$"
          mkdir -p ${XDG_DATA_HOME:-$HOME/.local/share}/swayimg
          last_file="${XDG_DATA_HOME:-$HOME/.local/share}/swayimg/last"
          trash="${HOME}/trash/1st-level/pic"
          rofi_cmd='rofi -dmenu -sort -matching fuzzy -no-plugins -no-only-match -theme swayimg -custom'
          pics_dir_default="$HOME/Pictures"
          pics_dir="${XDG_PICTURES_DIR:-$pics_dir_default}"

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
              s="$(ls -t "$rt"/swayimg-*.sock 2> /dev/null | head -n1 || true)"
              [ -n "$s" ] && [ -S "$s" ] && {
                printf '%s' "$s"
                return 0
              }
            fi
            return 1
          }

          _ipc_send() { # _ipc_send <command>
            local sock cmd
            cmd="$1"
            sock="$(_find_ipc_socket || true)"
            [ -n "$sock" ] || return 0
            if command -v socat > /dev/null 2>&1; then
              printf '%s\n' "$cmd" | socat - "UNIX-CONNECT:$sock" > /dev/null 2>&1 || true
            elif command -v ncat > /dev/null 2>&1; then
              printf '%s\n' "$cmd" | ncat -U "$sock" > /dev/null 2>&1 || true
            else
              return 0
            fi
          }

          # ---- swww helpers -----------------------------------------------------------
          ensure_swww() {
            # Start swww daemon if not running
            if ! swww query > /dev/null 2>&1; then
              swww init > /dev/null 2>&1 || true
              sleep 0.05
            fi
          }

          # Return maximum WxH among active outputs (fallback 1920x1080)
          screen_wh() {
            local wh
            if command -v swaymsg > /dev/null 2>&1 && command -v jq > /dev/null 2>&1; then
              wh="$(swaymsg -t get_outputs -r 2> /dev/null \
                | jq -r '[.[] | select(.active and .current_mode != null)
                            | {w:.current_mode.width|tonumber, h:.current_mode.height|tonumber, a:(.current_mode.width|tonumber)*(.current_mode.height|tonumber)}]
                           | if length>0 then (max_by(.a) | "\(.w)x\(.h)") else empty end' 2> /dev/null || true)"
            fi
            [ -n "${wh:-}" ] && printf '%s\n' "$wh" || printf '1920x1080\n'
          }

          # Render image to tmp file based on mode for swww
          # writes output path to $tmp_wall
          render_for_mode() {
            local mode="$1" file="$2" wh
            if ! command -v convert > /dev/null 2>&1; then
              return 1
            fi
            wh="$(screen_wh)"
            rm -f "$tmp_wall" 2> /dev/null || true
            case "$mode" in
              cover | full | fill)
                # cover: crop to fill screen from center
                convert "$file" -resize "${wh}^" -gravity center -extent "$wh" "$tmp_wall"
                ;; 
              center)
                # fit inside with borders, centered
                convert "$file" -resize "${wh}" -gravity center -background black -extent "$wh" "$tmp_wall"
                ;; 
              tile)
                # make tiled canvas of exact screen size
                convert -size "$wh" tile:"$file" "$tmp_wall"
                ;; 
              mono)
                convert "$file" -colors 2 "$tmp_wall"
                ;; 
              retro)
                convert "$file" -colors 12 "$tmp_wall"
                ;; 
              *) 
                # default to cover
                convert "$file" -resize "${wh}^" -gravity center -extent "$wh" "$tmp_wall"
                ;; 
            esac
          }

          # ---- helpers ---------------------------------------------------------------
          rotate() { # modifies file in-place
            angle="$1"
            shift
            while read -r file; do mogrify -rotate "$angle" "$file"; done
          }

          choose_dest() {
            # Fuzzy-pick a destination dir using zoxide history, limited to XDG_PICTURES_DIR
            local prompt="$1"
            local entries

            entries="$(
              { 
                command -v zoxide > /dev/null 2>&1 && zoxide query -l 2> /dev/null || true
              } \ 
                | awk -v pic="$pics_dir" 'index($0, pic) == 1' \
                | sed "s:^$HOME:~:" \
                | awk 'NF' \
                | sort -u
            )"

            if [ -z "$entries" ]; then
              entries="$(
                { 
                  printf '%s\n' "$pics_dir"
                  if command -v fd > /dev/null 2>&1; then
                    fd -td -d 3 . "$pics_dir" 2> /dev/null
                  else
                    find "$pics_dir" -maxdepth 3 -type d -print 2> /dev/null
                  fi
                } \ 
                  | sed "s:^$HOME:~:" \
                  | awk 'NF' \
                  | sort -u
              )"
            fi

            printf '%s\n' "$entries" \
              | sh -c "$rofi_cmd -p \"⟬$prompt⟭ ❯>\""
              | sed "s:^~:$HOME:"
          }

          proc() { # mv/cp with remembered last dest
            cmd="$1"
            file="$2"
            dest="${3:-}"
            printf '%s\n' "$file" | tee "$ff" > /dev/null

            if [ -z "${dest}" ]; then
              dest="$(choose_dest "$cmd" || true)"
            fi
            [ -z "${dest}" ] && exit 0
            if [ -d "$dest" ]; then
              # Avoid swayimg crash when current list ends after move: switch away first
              if [ "$cmd" = "mv" ]; then
                _ipc_send "prev_file"
              fi
              while read -r line; do
                "$cmd" "$(realpath "$line")" "$dest"
              done < "$ff"
              command -v zoxide > /dev/null 2>&1 && zoxide add "$dest" || true
              printf '%s %s\n' "$cmd" "$dest" > "$last_file"
            fi
          }

          repeat_action() { # repeat last mv/cp to same dir
            file="$1"
            [ -f "$last_file" ] || exit 0
            last="$(cat "$last_file")"
            cmd="$(printf '%s\n' "$last" | awk '{print $1}')"
            dest="$(printf '%s\n' "$last" | awk '{print $2}')"
            if [ "$cmd" = "mv" ] || [ "$cmd" = "cp" ]; then
              "$cmd" "$file" "$dest"
            fi
          }

          copy_name() { # copy absolute path to clipboard
            file="$1"
            printf '%s\n' "$(realpath "$file")" | wl-copy
            [ -x "$HOME/bin/pic-notify" ] && "$HOME/bin/pic-notify" "$file" || true
          }

          wall() { # wall <mode> <file> via swww
            local mode="$1" file="$2"
            ensure_swww
            render_for_mode "$mode" "$file" || return 0
            # Allow user to override transition opts via $SWWW_FLAGS
            swww img "${SWWW_IMAGE_OVERRIDE:-$tmp_wall}" ${SWWW_FLAGS:-} > /dev/null 2>&1 || true
            echo "$file" >> "${XDG_DATA_HOME:-$HOME/.local/share}/wl/wallpaper.list" 2> /dev/null || true
          }

          finish() { rm -f "$ff" "$tmp_wall" 2> /dev/null || true; }
          trap finish EXIT

          # ---- dispatch --------------------------------------------------------------
          action="${1:-}"
          file="${2:-}"

          case "$action" in
            rotate-left) printf '%s\n' "$file" | rotate 270 ;; 
            rotate-right) printf '%s\n' "$file" | rotate 90 ;; 
            rotate-180) printf '%s\n' "$file" | rotate 180 ;; 
            rotate-ccw) printf '%s\n' "$file" | rotate -90 ;; 
            copyname) copy_name "$file" ;; 
            repeat) repeat_action "$file" ;; 
            mv) proc mv "$file" "${3:-}" ;; 
            cp) proc cp "$file" "${3:-}" ;; 
            wall-mono) wall mono "$file" ;; 
            wall-fill) wall fill "$file" ;; 
            wall-full) wall full "$file" ;; 
            wall-tile) wall tile "$file" ;; 
            wall-center) wall center "$file" ;; 
            *) 
              echo "Unknown action: $action" >&2
              exit 2
              ;; 
          esac
        '';

        swdText = ''
          #!/usr/bin/env bash
          # swd: download a random wallpaper from wallhaven.cc with filters
          # Usage:
          #   swd [options]
          # Options:
          #   -C, --colors HEX[,HEX...]   dominant colors (e.g. 424153 or 424153,ffffff)
          #   -a, --atleast WxH           minimum resolution (default: 3840x2160)
          #   -p, --purity STR            purity flags (SFW=100, Sketchy=010, Both=110)
          #   -c, --categories STR        categories (General=100, Anime=010, People=001)
          #   -r, --ratios LIST           aspect ratios (e.g. 16x9,21x9)
          #   -s, --sorting MODE          latest|views|toplist|favorites|random
          #   -o, --order ORDER           asc|desc (default: desc)
          #   -l, --location DIR          download directory (default: $XDG_PICTURES_DIR/wl or ~/pic/wl)
          #   -k, --apikey KEY            Wallhaven API key (optional)
          #   -h, --help                  show this help


          IFS=$'\n\t'

          if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; then
            sed -n '2,14p' "$0" | sed 's/^# {0,1}//'; exit 0
          fi
          die(){ printf 'swd: %s\n' "$*" >&2; :; }
          need(){ command -v "$1" >/dev/null 2>&1 || printf 'swd: missing dependency: %s\n' "$1" >&2; }
          need curl
          need jq
          # TODO: create swd for unsplash
          location="${XDG_PICTURES_DIR:-$HOME/pic}/wl"
          atleast="3840x2160"
          purity="100"
          categories="100"
          order="desc"
          ratios="16x9"
          sorting="random"
          colors=""
          apikey="${WALLHAVEN_API_KEY:-}"

          # Set the dominant colors of the image
          # All           = Do not include for all
          # #660000 #990000 #cc0000 #cc3333 #ea4c88 #993399
          # #663399 #333399 #0066cc #0099cc #66cccc #77cc33
          # #669900 #336600 #666600 #999900 #cccc33 #cccc33
          # #cccc33 #ff9900 #ff6600 #cc6633 #996633 #663300
          # #000000 #999999 #cccccc #ffffff #424153
          # colors="424153"
          # Set the site address
          site="wallhaven.cc"

          # Translate long options to short and parse via getopts
          _args=()
          while (($#)); do
            case "$1" in
              --help) _args+=("-h"); shift ;; 
              --colors) _args+=("-C" "$2"); shift 2 ;; 
              --atleast) _args+=("-a" "$2"); shift 2 ;; 
              --purity) _args+=("-p" "$2"); shift 2 ;; 
              --categories) _args+=("-c" "$2"); shift 2 ;; 
              --ratios) _args+=("-r" "$2"); shift 2 ;; 
              --sorting) _args+=("-s" "$2"); shift 2 ;; 
              --order) _args+=("-o" "$2"); shift 2 ;; 
              --location) _args+=("-l" "$2"); shift 2 ;; 
              --apikey) _args+=("-k" "$2"); shift 2 ;; 
              --*) die "unknown option: $1" ;; 
              *) _args+=("$1"); shift ;; 
            esac
          done
          set -- "${_args[@]}"

          while getopts ":C:a:p:c:r:s:o:l:k:h" opt; do
            case "$opt" in
              C) colors="$OPTARG" ;; 
              a) atleast="$OPTARG" ;; 
              p) purity="$OPTARG" ;; 
              c) categories="$OPTARG" ;; 
              r) ratios="$OPTARG" ;; 
              s) sorting="$OPTARG" ;; 
              o) order="$OPTARG" ;; 
              l) location="$OPTARG" ;; 
              k) apikey="$OPTARG" ;; 
              h) sed -n '2,20p' "$0" | sed 's/^# {0,1}//'; exit 0 ;; 
              :) die "option -$OPTARG requires an argument" ;; 
              \?) die "unknown option: -$OPTARG" ;; 
            esac
          done
          shift $((OPTIND-1))

          # Build API URL instead of scraping HTML
          api_url="https://$site/api/v1/search?"
          [[ -n "$categories" ]] && api_url+="categories=$categories"
          [[ -n "$purity" ]] && api_url+="&purity=$purity"
          [[ -n "$order" ]] && api_url+="&order=$order"
          [[ -n "$colors" ]] && api_url+="&colors=$colors"
          [[ -n "$ratios" ]] && api_url+="&ratios=$ratios"
          [[ -n "$atleast" ]] && api_url+="&atleast=$atleast"
          api_url+="&page=$(($RANDOM % 30 + 1))"

          case "$sorting" in
            "latest") api_url+="&sorting=date_added" ;; 
            "views") api_url+="&sorting=views" ;; 
            "toplist") api_url+="&sorting=toplist" ;; 
            "favorites") api_url+="&sorting=favorites" ;; 
            *) api_url+="&sorting=random" ;; 
          esac

          # Read JSON and pick random wallpaper path (.data[].path)
          [[ -n "$colors" ]] && colors="${colors//#/}"
          [[ -n "$apikey" ]] && api_url+="&apikey=$apikey"
          json="$(curl -fsS --retry 3 --retry-delay 1 "$api_url")" || die "failed to query API"
          mapfile -t img_paths < <(jq -r '.data[]?.path' <<< "$json")
          if [[ ${#img_paths[@]} -eq 0 ]]; then
            die "no wallpapers found for the given filters"
          fi
          rand_img="${img_paths[$RANDOM % ${#img_paths[@]}]}"
          mkdir -p -- "$location"
          wallpaper="$location/${rand_img##*/}"
          curl -fsS --retry 3 --retry-delay 1 -o "$wallpaper" "$rand_img" >/dev/null || die "failed to download image"
          printf '%s\n' "$wallpaper"
        '';

        sxText = ''
          #!/usr/bin/env zsh
          # sx: view images in swayimg sorted by ctime (newest first)
          # Usage: sx [DIR...]

          IFS=$'\n\t'
          if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
            echo "Usage: sx [DIR...]" >&2
            exit 0
          fi

          # If no arguments provided, default to current directory
          if [[ "$#" -eq 0 ]]; then
            set -- "."
          fi

          swimg_bin="${HOME}/.local/bin/swayimg"
          [[ -x "$swimg_bin" ]] || swimg_bin="swayimg"
          if ! command -v "$swimg_bin" >/dev/null 2>&1; then
            print -u2 'sx: swayimg not found in PATH or ~/.local/bin'
            exit 1
          fi

          filter_ext() {
            if command -v ug >/dev/null 2>&1; then
              ug -iE '\.(jpe?g|png|gif|svg|webp|tiff|heif|heic|avif|ico|bmp)$'
            else
              grep -Ei '\.(jpe?g|png|gif|svg|webp|tiff|heif|heic|avif|ico|bmp)$'
            fi
          }

          "$swimg_bin" -C "${XDG_CONFIG_HOME:-$HOME/.config}/swayimg/config" -g -f -F <(
            # Follow symlinks and sort by ctime (newest first)
            find -L "$@" -type f -printf '%C@ %p\n' \
            | sort -rn \
            | cut -d ' ' -f 2- \
            | filter_ext
          )
        '';

        unlockText = ''
          #!/bin/sh
          # unlock: unlock SSH keys (optionally Yubikey) via expect using pass(1) secrets
          # Usage: unlock
          pp0="$(pass show ssh-key)"
          pp2="$(pass show wrk/ssh-key || true)" # unused fallback; kept for compatibility
          cleanup() { unset pp0 pp1 pp2 || true; }
          trap cleanup EXIT HUP INT TERM

          . /etc/profile
          pp0="$(pass show ssh-key)"
          pp2="$(pass show wrk/ssh-key)"
          if lsusb | grep -q "0407 Yubico"; then
              pp1="$(pass show pin)"
              expect << EOF
                  spawn "$XDG_CONFIG_HOME/zsh-nix/ylock"
                  expect "Enter passphrase"
                  send "$pp1\r"
                  expect eof
EOF
          fi
          expect << EOF
              spawn ssh-add $HOME/.ssh/id_neg
              expect "Enter passphrase"
              send "$pp0\r"
              expect eof
EOF
        '';

        vText = ''
          #!/bin/sh
          # v: open Neovim with system profile sourced
          # Usage: v [ARGS...]
          . /etc/profile
          SOCKET="/tmp/nvim.sock"

          # 1. Check if socket exists
          if [ -S "$SOCKET" ]; then
            # 2. Open file(s) in existing instance
            # Use --remote-silent to avoid blocking or errors if args empty
            if [ "$#" -gt 0 ]; then
                nvr --servername "$SOCKET" --remote-silent "$@"
            fi

            # 3. Raise Window (via raise script)
            raise --match "class:regex=^nwim$"
            # Previous lsof implementation removed in favor of raise script interaction
          else
            # 4. Start new instance acting as server
            # Use exec to replace shell process
            exec nvim --listen "$SOCKET" "$@"
          fi
          # vim:filetype=sh
        '';

        volText = ''
          #!/usr/bin/env zsh
          # vol: adjust PipeWire default sink volume via wpctl
          # Usage: vol [+DELTA|-DELTA]
          #   Example: vol +0.05 (increase), vol -0.05 (decrease)

          IFS=$'\n\t'
          if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || -z "${1:-}" ]]; then
            sed -n '2,4p' "$0" | sed 's/^# {0,1}//'; exit 0
          fi

          command -v wpctl >/dev/null 2>&1 || { print -u2 'vol: wpctl not found'; :; }

          sign(){
            case "$1" in
              -*) echo '-' ;; 
              +*) echo '+' ;; 
              *) echo '' ;; 
            esac
          }
          get_volume_(){ wpctl get-volume @DEFAULT_SINK@ }
          get_volume(){ get_volume_ | cut -d: -f2 | tr -d '[:space:]' }
          set_volume(){ wpctl set-volume @DEFAULT_SINK@ "$1" }
          set_volume_safe(){
              # Clamp to 1.00 when increasing
              set_volume "$(printf '%s %s' "$(get_volume)" "$1" | awk '{v=$1+$2; if (v>=1.0) print 1.00; else if (v<0) print 0.00; else print v}')"
          }

          case "$(sign "$1")" in
            '-') set_volume "$1" ;; 
            '+') set_volume_safe "$1" ;; 
             *) print -u2 'vol: expected +DELTA or -DELTA'; exit 2 ;; 
          esac
        '';

        wlText = ''
          #!/usr/bin/env nu
          # wl: set a random wallpaper from ~/pic/wl or ~/pic/black using swww
          # Usage: wl

          # best-effort ensure swww daemon is running (newer CLI ships it separately)
          if ((ps | where name == "swww-daemon" | length) == 0) {
            ^sh -c 'swww-daemon --quiet >/dev/null 2>&1 &' | ignore
            sleep 200ms
          }

          # Collect candidate images; shuffle and pick the first
          let allowed_ext = [bmp gif hdr ico jpg jpeg png tif tiff webp]
          let pics = (
            ls ...(glob ~/pic/{wl,black}/**/*)
            | where type == file
            | where {|row| 
                let ext = (try { $row.name | path parse | get extension } catch { "" } | str downcase)
                $ext != "" and ($allowed_ext | any {|e| $e == $ext})
              }
            | get name
          )
          if ($pics | length) == 0 { exit 1 }
          let pick = ($pics | shuffle | first)

          # Apply wallpaper with a smooth transition
          ^swww img --transition-fps 240 $pick
        '';

        # --- Content of scripts from packages/local-bin/scripts ---
        autoclickToggleText = ''
          #!/usr/bin/env bash
          set -euo pipefail

          PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/autoclick.pid"
          DELAY_MS="${1:-16}"
          # ydotoold defaults to a runtime-dir socket; ensure we point to it explicitly
          export YDOTOOL_SOCKET="${YDOTOOL_SOCKET:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/.ydotool_socket}"

          stop() {
            if [[ -f "$PIDFILE" ]]; then
              local pid
              pid=$(cat "$PIDFILE" 2>/dev/null || true)
              if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
                wait "$pid" 2>/dev/null || true
              fi
              rm -f "$PIDFILE"
              command -v notify-send >/dev/null 2>&1 && notify-send 'Autoclicker' 'Stopped'
            fi
            exit 0
          }

          if [[ -f "$PIDFILE" ]]; then
            stop
          fi

          if ! command -v ydotool >/dev/null 2>&1; then
            echo "autoclick-toggle: ydotool not found in PATH" >&2
            exit 1
          fi

          if ! [[ "$DELAY_MS" =~ ^[0-9]+$ ]]; then
            echo "autoclick-toggle: delay must be an integer number of milliseconds" >&2
            exit 1
          fi

          DELAY_S=$(awk "BEGIN { printf \"%.4f\", $DELAY_MS / 1000 }")

          (
            trap stop INT TERM
            while true; do
              ydotool click 0xC0
              sleep "$DELAY_S"
            done
          ) &
          daemon_pid=$!
          echo "$daemon_pid" >"$PIDFILE"

          if command -v notify-send >/dev/null 2>&1; then
            notify-send 'Autoclicker' "Started (${DELAY_MS} ms)"
          fi

          disown "$daemon_pid"
        '';

        hyprShortcutsText = ''
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
        '';

        journalCleanText = ''
          #!/usr/bin/env bash
          set -euo pipefail

          # Clean what can be cleaned without root:
          # - Try vacuuming user journal (if permitted) to a minimal retention window
          # - Truncate Hyprland runtime log
          # - Truncate optional per-user app logs under XDG cache

          keep_window="${1:-1d}"

          if command -v journalctl > /dev/null 2>&1; then
            echo "== journalctl --user disk usage (before) =="
            journalctl --user --disk-usage || true
            if journalctl --user --vacuum-time="${keep_window}" > /dev/null 2>&1; then
              echo "Vacuumed user journal to keep ${keep_window}"
            else
              echo "Skipping vacuum: insufficient permission to remove system journal files (needs root)" >&2
            fi
            echo "== journalctl --user disk usage (after) =="
            journalctl --user --disk-usage || true
          else
            echo "journalctl not available; skipping journal vacuum" >&2
          fi

          # Hyprland runtime log (safe to truncate)
          if [[ -n "${XDG_RUNTIME_DIR:-}" && -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
            hypr_log="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/hyprland.log"
            if [[ -f "${hypr_log}" ]]; then
              : > "${hypr_log}"
              echo "Truncated Hyprland log: ${hypr_log}"
            fi
          fi

          # Pyprland cache log (if present)
          if [[ -n "${XDG_CACHE_HOME:-}" ]]; then
            for f in "${XDG_CACHE_HOME}/pyprland.log" "${XDG_CACHE_HOME}/pyprland/pyprland.log"; do
              if [[ -f "${f}" ]]; then
                : > "${f}"
                echo "Truncated ${f}"
              fi
            done
          fi

          echo "Done."
        '';

        musicHighlevelText = ''
          #!/usr/bin/env python3
          """
          Extract Essentia highlevel classifications via streaming_extractor_music.

          Usage:
            music-highlevel [options] [PATH ...]

          Description:
            Runs Essentia's streaming_extractor_music over provided audio files or
            directories and emits the highlevel classifier outputs (genre, moods, etc.).
            Results can be printed in a human-readable form or as JSON per track.
          """
          import argparse
          import json
          import subprocess as sp
          import sys
          import tempfile
          from pathlib import Path
          from typing import Any, Dict, Iterable, List

          try:  # optional faster JSON
              import orjson  # type: ignore
          except Exception:  # pragma: no cover
              orjson = None

          AUDIO_EXTS = {
              ".mp3",
              ".flac",
              ".wav",
              ".ogg",
              ".m4a",
              ".opus",
              ".aac",
              ".wma",
              ".aiff",
              ".aif",
          }

          # Commonly useful highlevel taxonomies Essentia ships models for.
          DEFAULT_TAXONOMIES = [
              "genre_dortmund",
              "genre_tzanetakis",
              "genre_rosamerica",
              "danceability",
              "moods_mirex",
              "moods_happiness",
              "moods_sadness",
              "moods_relaxed",
              "moods_aggressive",
              "tonal_atonal",
          ]


          def walk_inputs(paths: Iterable[Path]) -> List[Path]:
              files: List[Path] = []
              for p in paths:
                  if p.is_dir():
                      for child in sorted(p.rglob("*")):
                          if child.is_file() and child.suffix.lower() in AUDIO_EXTS:
                              files.append(child)
                  elif p.is_file():
                      files.append(p)
              return files


          def run_extractor(audio: Path) -> Dict[str, Any] | None:
              with tempfile.TemporaryDirectory() as td:
                  out_json = Path(td) / "highlevel.json"
                  cmd = ["streaming_extractor_music", str(audio), str(out_json)]
                  try:
                      sp.run(cmd, check=True, stdout=sp.DEVNULL, stderr=sp.DEVNULL)
                  except sp.CalledProcessError:
                      print(f"[music-highlevel] extractor failed: {audio}", file=sys.stderr)
                      return None
                  try:
                      data = out_json.read_bytes()
                      if orjson:
                          return orjson.loads(data)
                      return json.loads(data.decode("utf-8"))
                  except Exception as exc:
                      print(f"[music-highlevel] failed reading output for {audio}: {exc}", file=sys.stderr)
                      return None


          def truncate_probs(prob_dict: Dict[str, Any], top: int) -> List[Dict[str, float | str]]:
              try:
                  items = [(label, float(score)) for label, score in prob_dict.items()]
              except Exception:
                  return []
              items.sort(key=lambda x: x[1], reverse=True)
              if top > 0:
                  items = items[:top]
              return [{"label": label, "score": score} for label, score in items]


          def extract_highlevel(highlevel: Dict[str, Any], selected: List[str], top: int) -> Dict[str, Any]:
              result: Dict[str, Any] = {}
              for name, payload in highlevel.items():
                  if selected and name not in selected:
                      continue
                  if not isinstance(payload, dict):
                      continue
                  entry: Dict[str, Any] = {}
                  probs = payload.get("probability")
                  if isinstance(probs, dict):
                      vals = truncate_probs(probs, top)
                      if vals:
                          entry["candidates"] = vals
                  elif isinstance(probs, (int, float)):
                      entry["score"] = float(probs)
                  value = payload.get("value")
                  if isinstance(value, str):
                      entry["value"] = value
                  elif isinstance(value, (int, float)):
                      entry["value"] = float(value)
                  if entry:
                      result[name] = entry
              return result


          def emit(result: Dict[str, Any], json_output: bool) -> None:
              if json_output:
                  payload = orjson.dumps(result).decode("utf-8") if orjson else json.dumps(result, ensure_ascii=False)
                  print(payload)
                  return
              path = result.get("path", "<unknown>")
              print(path)
              highlevel = result.get("highlevel", {})
              if not highlevel:
                  print("  (no highlevel data)")
                  return
              for name, data in highlevel.items():
                  value = data.get("value")
                  candidates = data.get("candidates")
                  score = data.get("score")
                  line = f"  {name}:"
                  if value is not None:
                      line += f" value={value}"
                  if score is not None:
                      line += f" score={score:.3f}"
                  print(line)
                  if isinstance(candidates, list):
                      for item in candidates:
                          print(f"    {item['score']:.3f}\t{item['label']}")


          def parse_args() -> argparse.Namespace:
              ap = argparse.ArgumentParser(description="Inspect Essentia highlevel classifiers for audio files")
              ap.add_argument("paths", nargs="*", help="audio files or directories; defaults to current track via playerctl")
              ap.add_argument("--top", type=int, default=3, help="top probabilities per taxonomy to display")
              ap.add_argument(
                  "--taxonomies",
                  nargs="*",
                  default=[],
                  help="specific highlevel taxonomies to include (defaults to a common subset)",
              )
              ap.add_argument("--json", action="store_true", help="emit JSON per track")
              return ap.parse_args()


          def main() -> int:
              args = parse_args()
              if args.taxonomies:
                  selected = args.taxonomies
              else:
                  selected = DEFAULT_TAXONOMIES

              inputs = [Path(p).expanduser() for p in args.paths]
              if not inputs:
                  # Fall back to current track via playerctl if available.
                  try:
                      current = sp.check_output(["playerctl", "metadata", "xesam:url"], text=True).strip()
                  except Exception:
                      current = ""
                  if current.startswith("file://"):
                      from urllib.parse import urlparse, unquote

                      parsed = urlparse(current)
                      if parsed.path:
                          inputs = [Path(unquote(parsed.path))]
              if not inputs:
                  print("[music-highlevel] no inputs provided", file=sys.stderr)
                  return 1

              files = walk_inputs(inputs)
              if not files:
                  print("[music-highlevel] no audio files found", file=sys.stderr)
                  return 1

              for audio in files:
                  data = run_extractor(audio)
                  if data is None:
                      continue
                  highlevel = data.get("highlevel")
                  if not isinstance(highlevel, dict):
                      print(f"[music-highlevel] missing highlevel section: {audio}", file=sys.stderr)
                      continue
                  extracted = extract_highlevel(highlevel, selected, args.top)
                  result = {"path": str(audio), "highlevel": extracted}
                  emit(result, args.json)
              return 0


          if __name__ == "__main__":
              raise SystemExit(main())
        '';

        pass2colText = ''
          #!/usr/bin/env bash
          set -euo pipefail

          store_dir="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
          [ -d "$store_dir" ] || exit 0

          # Collect entries: strip .gpg and leading ./, ignore .gpg-id files
          mapfile -t entries < <(cd "$store_dir" && \
            find . -type f -name '*.gpg' ! -path './.git/*' -printf '%P\n' 2>/dev/null \
            | grep -vE '(^|/)\.gpg-id$' \
            | sed 's#^\./##; s/\.gpg$//' \
            | LC_ALL=C sort)

          count=${#entries[@]}
          [ "$count" -gt 0 ] || exit 0

          # Two columns: lines = ceil(count/2), clamp to a sensible max (12)
          lines=$(( (count + 1) / 2 ))
          if [ "$lines" -gt 12 ]; then lines=12; fi

          sel=$(printf '%s\n' "${entries[@]}" \
            | rofi -dmenu -p 'pass ❯>' -columns 2 -lines "$lines" -theme pass)

          [ -n "${sel:-}" ] || exit 0

          # Prefer OTP codes when present to avoid pasting otpauth URIs
          if otp_raw=$(pass otp code -- "$sel" 2>/dev/null); then
            otp_code=$(printf '%s' "$otp_raw" | head -n1 | tr -d '\r\n')
            if [ -n "$otp_code" ]; then
              if command -v wl-copy >/dev/null 2>&1; then
                printf '%s' "$otp_code" | wl-copy
              else
                # Fallback to pass otp -c (handles clipboard expiration)
                pass otp -c -- "$sel" >/dev/null 2>&1 || true
              fi
              command -v notify-send >/dev/null 2>&1 && notify-send "pass" "OTP copied: $sel" || true
              exit 0
            fi
          fi

          # Capture first line for password fallback and to detect raw otpauth secrets
          pw=$(pass show -- "$sel" 2>/dev/null | head -n1 || true)
          pw=$(printf '%s' "$pw" | tr -d '\r\n')

          # Guard against leaking otpauth URIs if pass-otp is unavailable
          if [ -n "$pw" ] && [[ "$pw" == otpauth://* ]]; then
            # Try clipboard fallback via pass otp -c, otherwise fail quietly
            if ! pass otp -c -- "$sel" >/dev/null 2>&1; then
              command -v notify-send >/dev/null 2>&1 && notify-send "pass" "OTP entry needs pass-otp: $sel" || true
            fi
            exit 0
          fi

          # Copy password (first line of pass show) to clipboard
          if [ -n "$pw" ]; then
            if command -v wl-copy >/dev/null 2>&1; then
              printf '%s' "$pw" | wl-copy
            else
              # Fallback to pass -c (may use xclip/xsel)
              pass -c -- "$sel" >/dev/null 2>&1 || true
            fi
            command -v notify-send >/dev/null 2>&1 && notify-send "pass" "Copied: $sel" || true
          fi
        '';

        punzipText = ''
          #!/bin/sh
          # punzip: simple unzip helper with optional -d DIR target
          # Usage: punzip [-d DIR] FILE.zip

          set -eu
          dest=""
          if [ "${1:-}" = "-d" ]; then
            dest="${2:-}"
            [ -n "$dest" ] || { echo "punzip: missing DIR for -d" >&2; exit 2; }
            shift 2 || true
          fi
          [ -n "${1:-}" ] || { echo "punzip: missing FILE.zip" >&2; exit 2; }
          zipfile="$1"
          case "$zipfile" in
            *.zip|*.ZIP) :;; 
            *) echo "punzip: not a zip: $zipfile" >&2; exit 2;; 
          esac
          if [ -n "$dest" ]; then
            mkdir -p -- "$dest"
            exec unzip -o "$zipfile" -d "$dest"
          else
            exec unzip -o "$zipfile"
          fi
        '';

        # Special case: ren needs path substitution for libs as well
        renText = lib.replaceStrings ["@LIBPP@" "@LIBCOLORED@"] [libpp libcolored] ''
          #!/usr/bin/env python3

          """ Pretty file renamer (normalize to personal naming scheme).

          Usage:
              ren [-i] FILES ...

          Options:
              -i      apply changes in-place (otherwise only print the mapping)
              FILES   input file list

          Created by :: Neg
          email :: <serg.zorg@gmail.com>
          year :: 2021
          """

          # Ensure packaged libraries are on sys.path (no env required)
          import sys
          sys.path.insert(0, '@LIBPP@')
          sys.path.insert(0, '@LIBCOLORED@')

          import os
          import re

          # Prefer neg_pretty_printer; fall back to legacy pretty_printer if present.
          try:
              from neg_pretty_printer import PrettyPrinter  # type: ignore
          except Exception:
              try:
                  import pretty_printer as _pp  # type: ignore
                  PrettyPrinter = _pp.PrettyPrinter  # type: ignore
              except Exception:
                  PrettyPrinter = None  # library unavailable; print plain mapping

          def fancy_name(filename, file=False):
              """ Some magic to return beautiful filename """

              filename = re.sub(r'[ _\t\.]+', "·", filename)
              filename = re.sub(r'·*-·*', '-', filename)
              filename = re.sub(r'[\,\_-]', '-', filename)
              filename = re.sub(r'[+·\.]*-[+·\.]*', '-', filename)
              filename = re.sub(r'[+·\.]*:[+·\.]*', ':', filename)

              # filename = re.sub(r'[><\\]+', "", filename)
              filename = re.sub(r'\(+', "[", filename)
              filename = re.sub(r'\)+', "]", filename)
              filename = re.sub(r"[\'\`]", "=", filename)
              filename = re.sub(r'^[-.()+·\.]+', "", filename)
              filename = re.sub(r'[-.()+·\.]+$', "", filename)

              if file:
                  return '.'.join(filename.rsplit('·', 1))

              return filename

          def main():
              """ Pretty-printing autorenamer """
              # Prefer docopt, but allow argparse fallback to avoid hard dependency
              files = []
              file_rename = False
              try:
                  from docopt import docopt  # type: ignore
                  cmd_args = docopt(__doc__, version='1.0')
                  files = cmd_args['FILES']
                  file_rename = cmd_args['-i']
              except Exception:
                  import argparse
                  p = argparse.ArgumentParser(prog='ren', description='Pretty file renamer')
                  p.add_argument('-i', action='store_true', help='apply changes in-place')
                  p.add_argument('FILES', nargs='+', help='input files')
                  args = p.parse_args()
                  files = args.FILES
                  file_rename = args.i
              for fname in files:
                  if not os.path.exists(fname):
                      break
                  dir_name = os.path.dirname(fname)
                  input_name = os.path.basename(fname)

                  if os.path.isdir(fname):
                      output_name = fancy_name(input_name)
                  else:
                      output_name = fancy_name(input_name, file=True)

                  if file_rename:
                      pref = ''
                      if dir_name:
                          pref = dir_name + '/' 
                      os.rename(pref + input_name, pref + output_name)
                  if PrettyPrinter:
                      pp = PrettyPrinter
                      dir_out = pp.fancy_file(dir_name) if dir_name else ''
                      print(
                          f"{pp.prefix()}{dir_out}"
                          f"{pp.fancy_file(input_name)} -> {pp.fancy_file(output_name)}"
                      )
                  else:
                      pref = (dir_name + '/') if dir_name else ''
                      print(f"{pref}{input_name} -> {output_name}")

          main()
        '';

        # Special case: vid-info needs path substitution for libs
        vidInfoText = lib.replaceStrings ["@LIBPP@" "@LIBCOLORED@"] [libpp libcolored] ''
          #!/usr/bin/env python3

          """Video info pretty-printer.

          Usage:
              vid-info FILES ...

          Description:
              Prints a one-line summary per file (via ffprobe):
              - resolution (WxH), duration, size (MiB), overall bitrate (kbps),
                frame rate (fps), audio sample rate (kHz) and bitrate (kbps).

          Options:
              FILES   input video files

          Created by :: Neg
          email :: <serg.zorg@gmail.com>
          year :: 2022

          """

          # Ensure packaged libraries are on sys.path (no env required)
          import sys

          sys.path.insert(0, "@LIBPP@")
          sys.path.insert(0, "@LIBCOLORED@")

          import os
          import subprocess
          import json
          import math
          import datetime
          from enum import Enum
          import shutil

          from neg_pretty_printer import PrettyPrinter


          class SizeUnit(Enum):
              """Enum for size units"""

              BYTES = 1
              KIB = 2
              MIB = 3
              GIB = 4
              TIB = 5


          def convert_unit(size_in_bytes, unit):
              """Convert the size from bytes to other units like KB, MB or GB"""
              if unit == SizeUnit.KIB:
                  return size_in_bytes / 0x400
              if unit == SizeUnit.MIB:
                  return size_in_bytes / (0x400 * 0x400)
              if unit == SizeUnit.GIB:
                  return size_in_bytes / (0x400 * 0x400 * 0x400)
              if unit == SizeUnit.TIB:
                  return size_in_bytes / (0x400 * 0x400 * 0x400 * 0x400)
              return size_in_bytes


          def media_info(filename: str):
              """Extract media info by filename via ffprobe (JSON)."""
              if not shutil.which("ffprobe"):
                  print("[vid-info] missing ffprobe in PATH", file=sys.stderr)
                  return
              try:
                  proc = subprocess.run(
                      [
                          "ffprobe",
                          "-v",
                          "error",
                          "-show_format",
                          "-show_streams",
                          "-print_format",
                          "json",
                          str(filename),
                      ],
                      check=True,
                      stdout=subprocess.PIPE,
                      stderr=subprocess.PIPE,
                      text=True,
                  )
              except subprocess.CalledProcessError as e:
                  print(
                      f"[vid-info] ffprobe failed for {filename}: {e.stderr.strip()}",
                      file=sys.stderr,
                  )
                  return

              try:
                  ret = json.loads(proc.stdout)
              except Exception as e:
                  print(
                      f"[vid-info] bad ffprobe JSON for {filename}: {e}", file=sys.stderr
                  )
                  return

              pp = PrettyPrinter
              out, vid_frame_rate = "", ""
              audio_bitrate, audio_sample_rate = "", ""
              if not ret.get("streams", []):
                  return
              for stream in ret.get("streams", []):
                  if stream.get("codec_type") == "video":
                      w = stream.get("width")
                      h = stream.get("height")
                      if w and h:
                          out += pp.wrap(f"{w}x{h}")
                      afr = stream.get("avg_frame_rate") or ""
                      try:
                          num, den = afr.split("/") if "/" in afr else (afr, "1")
                          num_f = float(num)
                          den_f = float(den)
                          if den_f:
                              vid_frame_rate = round(num_f / den_f)
                      except Exception:
                          pass
                  if stream.get("codec_type") == "audio":
                      br = stream.get("bit_rate")
                      if br:
                          try:
                              audio_bitrate = math.floor(
                                  convert_unit(float(br), SizeUnit.KIB)
                              )
                          except Exception:
                              audio_bitrate = ""
                      sr = stream.get("sample_rate")
                      try:
                          if sr:
                              audio_sample_rate = float(sr) / 1000
                      except Exception:
                          audio_sample_rate = ""

              file_format = ret["format"]

              out += pp.wrap(
                  str(
                      datetime.timedelta(
                          seconds=math.floor(float(file_format["duration"]))
                      )
                  )
              )

              size = math.floor(convert_unit(float(file_format["size"]), SizeUnit.MIB))
              out += pp.size(str(size), "MIB")

              video_bitrate = math.floor(
                  convert_unit(float(file_format["bit_rate"]), SizeUnit.KIB)
              )
              out += pp.size(str(video_bitrate), "kbps", pref="vidbrate")
              if vid_frame_rate:
                  out += pp.wrap(str(vid_frame_rate), postfix="fps")

              if audio_sample_rate != "":
                  out += pp.size(str(audio_sample_rate), "K", pref="")
              if str(audio_bitrate):
                  out += pp.size(str(audio_bitrate), "kbps", pref="audbrate")

              print(out)


          def main():
              """Entry point"""
              # Prefer docopt, but allow fallback to argv if not available
              try:
                  from docopt import docopt  # type: ignore

                  cmd_args = docopt(__doc__, version="1.0")
                  files = cmd_args["FILES"]
              except Exception:
                  files = sys.argv[1:]

              pp = PrettyPrinter
              print_cwd, dir_name = False, ""

              for fname in files:
                  if not os.path.exists(fname):
                      continue
                  if os.path.dirname(fname):
                      dir_name = os.path.dirname(fname)
                  elif print_cwd:
                      dir_name = os.getcwd()

                  dir_name_out = ""
                  if dir_name and dir_name != ".":
                      dir_name_out = pp.fancy_file(dir_name)
                  input_name = os.path.basename(fname)
                  print(f"{pp.prefix()}{dir_name_out}{pp.fancy_file(input_name)}")
                  media_info(fname)


          if __name__ == "__main__":
              main()
        ''
      };
    }
  ])