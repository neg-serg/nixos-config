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
# Links are added before the ones that no longer belong are pruned, and the
# steady state is checked against the exact set it wants: a link that appears
# from outside (set-default.sh re-runs on every wireplumber restart, and
# WirePlumber itself re-links streams to the default sink) is removed instead of
# sitting there in parallel with the DSP path.
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
said=

log() { printf '%s camilladsp-route: %s\n' "$("$date" '+%F %T')" "$*"; }

# A missing target would otherwise be retried (and logged) every two seconds
# forever; say it once per reason, and say it again after the graph comes back.
say_once() {
  [[ $said == "$1" ]] && return 0
  said=$1
  log "$2"
}

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

# A port exists even while it has no links, which `pw-link -l` does not show.
port_exists() { # $1 = node:port
  "$pwLink" -i 2> /dev/null | "$grep" -qxF "$1" \
    || "$pwLink" -o 2> /dev/null | "$grep" -qxF "$1"
}

add() { "$pwLink" "$1" "$2" 2> /dev/null || true; }
del() { "$pwLink" -d "$1" "$2" 2> /dev/null || true; }

# Drop every link of a port except the one that belongs there. Reading the list
# line by line keeps a node name with a space (PipeWire allows one) a single
# argument; word splitting would turn it into three failed `pw-link -d` calls.
prune_sources() { # $1 = capture port, $2 = the only source it should have ("" for none)
  local src
  while IFS= read -r src; do
    [[ -z $src || $src == "$2" ]] && continue
    del "$src" "$1"
  done < <(sources_to "$1")
}

prune_dests() { # $1 = output port, $2 = the only destination it should have ("" for none)
  local dst
  while IFS= read -r dst; do
    [[ -z $dst || $dst == "$2" ]] && continue
    del "$1" "$dst"
  done < <(dests_of "$1")
}

# Exactly the wanted link, and nothing else, on that port.
only_sources() { # $1 = capture port, $2 = the wanted source
  local src n=0
  while IFS= read -r src; do
    [[ -z $src ]] && continue
    ((n++))
    [[ $src == "$2" ]] || return 1
  done < <(sources_to "$1")
  ((n == 1))
}

only_dests() { # $1 = output port, $2 = the wanted destination
  local dst n=0
  while IFS= read -r dst; do
    [[ -z $dst ]] && continue
    ((n++))
    [[ $dst == "$2" ]] || return 1
  done < <(dests_of "$1")
  ((n == 1))
}

dsp_up() {
  "$pwLink" -i 2> /dev/null | "$grep" -qxF "$CAP:input_FL" \
    && "$pwLink" -o 2> /dev/null | "$grep" -qxF "$PB:output_FL"
}

# The four links the insert is, both ways, and nothing else on the two DSP ports.
route_complete() {
  has_link "$GAME:output_FL" "$CAP:input_FL" \
    && has_link "$GAME:output_FR" "$CAP:input_FR" \
    && has_link "$PB:output_FL" "$AES_L" \
    && has_link "$PB:output_FR" "$AES_R" \
    && ! has_link "$GAME:output_FL" "$AES_L" \
    && ! has_link "$GAME:output_FR" "$AES_R" \
    && only_sources "$CAP:input_FL" "$GAME:output_FL" \
    && only_sources "$CAP:input_FR" "$GAME:output_FR" \
    && only_dests "$PB:output_FL" "$AES_L" \
    && only_dests "$PB:output_FR" "$AES_R"
}

# Add first, prune after: when a port vanished between the check and the call,
# the working path is still there instead of having been taken down already.
route_dsp() {
  add "$GAME:output_FL" "$CAP:input_FL"
  add "$GAME:output_FR" "$CAP:input_FR"
  add "$PB:output_FL" "$AES_L"
  add "$PB:output_FR" "$AES_R"
  prune_sources "$CAP:input_FL" "$GAME:output_FL"
  prune_sources "$CAP:input_FR" "$GAME:output_FR"
  prune_dests "$PB:output_FL" "$AES_L"
  prune_dests "$PB:output_FR" "$AES_R"
  # Exactly one path to AES: the DSP's.
  del "$GAME:output_FL" "$AES_L"
  del "$GAME:output_FR" "$AES_R"
  del "$GAME:output_FL" "$STRAY_L"
  del "$GAME:output_FR" "$STRAY_R"
}

route_direct() {
  add "$GAME:output_FL" "$AES_L"
  add "$GAME:output_FR" "$AES_R"
  del "$GAME:output_FL" "$STRAY_L"
  del "$GAME:output_FR" "$STRAY_R"
}

while :; do
  # Nothing can be routed while one of the two ends is absent. While that lasts,
  # a live DSP stream is also taken off every sink it has: with its AES target
  # gone, WirePlumber's own re-link would feed the playback stream into
  # game-stereo, which is the input of the capture stream — a loop.
  if ! port_exists "$GAME:output_FL" || ! port_exists "$AES_L"; then
    if dsp_up; then
      prune_dests "$PB:output_FL" ""
      prune_dests "$PB:output_FR" ""
    fi
    say_once waiting "route: waiting for game-stereo and the RME AES pair"
    "$sleep" 2
    continue
  fi
  said=

  if dsp_up; then want=dsp; else want=direct; fi
  if [[ $want != $state ]]; then
    if [[ $want == dsp ]]; then route_dsp; else route_direct; fi
    log "route: $want"
    state=$want
  elif [[ $want == dsp ]]; then
    route_complete || {
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
