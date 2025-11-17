#!/bin/sh
# main-menu: rofi-driven helper actions for music/clipboard/network/etc
# Usage: main-menu
# shellcheck shell=sh

IFS=' 	
'

items=$(
  cat << 'EOF'
 Title:title_copy
 Artist:artist_copy
 Album:album_copy
 Path:path_copy
 PipeWire Output:pipewire_output
 ALSA Output:alsa_output
 Translate:translate
 Termbin:termbin
EOF
)

generate_menu() {
  # Plain text rows (no markup) for reliability across rofi versions
  printf '%s\n' "$items" | awk -F ':' 'NF {print $1}'
}

# Helpers for JSON from rmpc-song
_song_json() { rmpc song 2> /dev/null; } # prints JSON for current song
jq_str() { jq -r "$1 // empty"; }

title_copy() {
  # Emulate `mpc current`: "Artist - Title" when possible, else Title, else empty
  _song_json | jq -r 'if .metadata.artist and .metadata.title then "\(.metadata.artist) - \(.metadata.title)"
                        else (.metadata.title // .metadata.name // "") end' | wl-copy
}

album_copy() { _song_json | jq_str '.metadata.album' | wl-copy; }
artist_copy() { _song_json | jq_str '.metadata.artist' | wl-copy; }

path_copy() {
  mpd_music_dir="${XDG_MUSIC_DIR:-$HOME/Music}"
  file=$(_song_json | jq_str '.file')
  [ -n "$file" ] && printf '%s/%s\n' "$mpd_music_dir" "$file" | wl-copy
}

pipewire_output() {
  rmpc-pause
  rmpc-enableoutput PipeWire
  rmpc-disableoutput "$dac_name"
  rmpc-play
}

alsa_output() {
  timeout="5s"
  rmpc-pause
  rmpc-enableoutput "$dac_name"
  rmpc-disableoutput PipeWire
  rmpc-play
  sleep "$timeout"
  rmpc-play
}

translate() {
  text="$(wl-paste)"
  translate="$(trans -brief :ru "$text")"
  notify-send -t $((${#text} * 150)) "$translate"
  play-sound "cyclist.ogg"
}

termbin() {
  url=$(wl-paste | nc termbin.com 9999)
  echo "$url" | wl-copy
  notify-send "$url copied to clipboard"
  play-sound "direct.ogg"
}

handler() {
  while IFS= read -r line; do
    label=$(printf '%s' "$line")
    [ -z "$label" ] && continue
    fn=$(printf '%s\n' "$items" | awk -F ':' -v L="$label" 'NF && $1==L{print $2; exit}')
    [ -n "$fn" ] && "$fn"
  done
}

dac_name='RME ADI-2/4 PRO SE'
set -- -auto-select -b -theme menu-columns -dmenu -p 'menu ❯>' \
  -columns 6 -lines 4
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  sed -n '2,2p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi
# no eval; pass options directly
generate_menu | rofi "$@" | handler
