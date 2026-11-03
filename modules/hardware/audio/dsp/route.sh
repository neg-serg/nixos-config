# Keep the CamillaDSP insert wired: game-stereo -> DSP -> RME AES.
#
# Both ends of the DSP config are the ALSA `pipewire` PCM, so the insert is two
# PipeWire streams that exist only while a config is running and are recreated
# on every reload (camilladsp closes and reopens both devices). A one-shot unit
# cannot own that wiring; this loop does:
#
#   * streams present -> route game-stereo's loopback outputs into the capture
#     stream, route the playback stream to the RME AES pair, and drop the
#     direct loopback -> RME links (two paths would double the audio);
#   * streams gone    -> restore the direct links, so a dead or reloading DSP
#     never costs the machine its sound.
#
# The RME ports follow files/media/hdspe-routing.yaml (aes = channels 2/3) and
# the node name is the one modules/hardware/audio/hdspe/set-default.sh owns.
set -u

pwLink="@pwLink@/bin/pw-link"
awk="@awk@/bin/awk"
grep="@grep@/bin/grep"
sleep="@sleep@/bin/sleep"
date="@date@/bin/date"

RME=alsa_output.pci-0000_05_00.0.pro-output-0
GAME=playback.game-stereo
CAP=alsa_capture.camilladsp
PB=alsa_playback.camilladsp
AES_L=$RME:playback_AUX2
AES_R=$RME:playback_AUX3
# WirePlumber auto-links the loopback to the RME's first (analog) pair on every
# restart; set-default.sh drops the same two, this keeps them off in between.
STRAY_L=$RME:playback_AUX0
STRAY_R=$RME:playback_AUX1

state=unknown

log() { printf '%s camilladsp-route: %s\n' "$("$date" '+%F %T')" "$*"; }

# One direction of a link line from `pw-link -l`: the port header line is the
# bare "node:port", the links under it start with a tab/space.
sources_to() { # $1 = destination port
  "$pwLink" -l 2> /dev/null | "$awk" -v t="$1" '
    $0 == t { f = 1; next }
    /^[^ \t]/ { f = 0 }
    f && $1 == "|<-" { print $2 }'
}

dests_of() { # $1 = source port
  "$pwLink" -l 2> /dev/null | "$awk" -v s="$1" '
    $0 == s { f = 1; next }
    /^[^ \t]/ { f = 0 }
    f && $1 == "|->" { print $2 }'
}

has_link() { # $1 = source, $2 = destination
  "$pwLink" -l 2> /dev/null | "$awk" -v s="$1" -v d="$2" '
    $0 == s { f = 1; next }
    /^[^ \t]/ { f = 0 }
    f && $1 == "|->" && $2 == d { found = 1 }
    END { exit !found }'
}

add() { "$pwLink" "$1" "$2" 2> /dev/null || true; }
del() { "$pwLink" -d "$1" "$2" 2> /dev/null || true; }

dsp_up() {
  "$pwLink" -i 2> /dev/null | "$grep" -qxF "$CAP:input_FL" \
    && "$pwLink" -o 2> /dev/null | "$grep" -qxF "$PB:output_FL"
}

route_dsp() {
  # Whatever auto-linked the fresh streams (capture from the default source,
  # playback into the default sink game-stereo) or is left over from the
  # previous config has to go first — feeding the playback stream back into the
  # sink whose output feeds the capture stream is the one loop to avoid.
  for p in "$CAP:input_FL" "$CAP:input_FR"; do
    for src in $(sources_to "$p"); do del "$src" "$p"; done
  done
  for p in "$PB:output_FL" "$PB:output_FR"; do
    for dst in $(dests_of "$p"); do del "$p" "$dst"; done
  done
  # Exactly one path to AES: the DSP's.
  del "$GAME:output_FL" "$AES_L"
  del "$GAME:output_FR" "$AES_R"
  del "$GAME:output_FL" "$STRAY_L"
  del "$GAME:output_FR" "$STRAY_R"
  add "$GAME:output_FL" "$CAP:input_FL"
  add "$GAME:output_FR" "$CAP:input_FR"
  add "$PB:output_FL" "$AES_L"
  add "$PB:output_FR" "$AES_R"
}

route_direct() {
  for p in "$PB:output_FL" "$PB:output_FR"; do
    for dst in $(dests_of "$p"); do del "$p" "$dst"; done
  done
  del "$GAME:output_FL" "$STRAY_L"
  del "$GAME:output_FR" "$STRAY_R"
  add "$GAME:output_FL" "$AES_L"
  add "$GAME:output_FR" "$AES_R"
}

while :; do
  if dsp_up; then want=dsp; else want=direct; fi
  if [[ "$want" != "$state" ]]; then
    if [[ "$want" == dsp ]]; then route_dsp; else route_direct; fi
    log "route: $want"
    state=$want
  elif [[ "$want" == dsp ]]; then
    # Steady state, but WirePlumber re-links new streams to the default sink and
    # set-default.sh re-runs on its own schedule: repair a missing link, and
    # leave the graph alone when everything is already in place (a full relink
    # costs a click).
    has_link "$GAME:output_FL" "$CAP:input_FL" \
      && has_link "$GAME:output_FR" "$CAP:input_FR" \
      && has_link "$PB:output_FL" "$AES_L" \
      && has_link "$PB:output_FR" "$AES_R" \
      || {
        route_dsp
        log "route: repaired"
      }
  else
    has_link "$GAME:output_FL" "$AES_L" \
      && has_link "$GAME:output_FR" "$AES_R" \
      || {
        route_direct
        log "route: repaired (direct)"
      }
  fi
  "$sleep" 2
done
