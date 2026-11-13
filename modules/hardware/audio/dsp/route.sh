# Keep the CamillaDSP insert wired: game-stereo -> DSP -> RME AES.
#
# Both ends of the DSP config are the native PipeWire backend, so the insert is
# two filter nodes that exist only while a config is running and are recreated
# on every reload. A one-shot unit cannot own that wiring; this loop does:
#
#   * streams present -> route game-stereo's loopback outputs into the capture
#     stream, route the playback stream to the RME AES pair, and drop the
#     direct loopback -> RME links (two paths would double the audio);
#   * streams gone    -> restore the direct links, so a dead or reloading DSP
#     never costs the machine its sound;
#   * host in the path -> the matrix tab (or a hand-run Carla project) has put
#     a VST host between a stream and its destination: keep the host's four
#     links, drop the direct cable, and do not prune a half-made insert while
#     its owner is still wiring it.
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
pwMeta="@pwLink@/bin/pw-metadata"
awk="@awk@/bin/awk"
grep="@grep@/bin/grep"
sleep="@sleep@/bin/sleep"
date="@date@/bin/date"
systemctl="@systemctl@/bin/systemctl"
wpctl="@wpctl@/bin/wpctl"

RME=alsa_output.pci-0000_05_00.0.pro-output-0
GAME=playback.game-stereo
CAP=camilladsp-capture
PB=camilladsp-playback
AES_L=$RME:playback_AUX2
AES_R=$RME:playback_AUX3
# WirePlumber auto-links the loopback to the RME's first (analog) pair on every
# restart; set-default.sh drops the same two, this keeps them off in between.
STRAY_L=$RME:playback_AUX0
STRAY_R=$RME:playback_AUX1

state=unknown
said=
host_grace=0
host_guard=0
idle=0
last_start=0

log() { printf '%s camilladsp-route: %s\n' "$("$date" '+%F %T')" "$*"; }

# A missing target would otherwise be retried (and logged) every two seconds
# forever; say it once per reason, and say it again after the graph comes back.
say_once() {
  [[ $said == "$1" ]] && return 0
  said=$1
  log "$2"
}

# A port owned by the VST host. While a host node is present the pruners leave
# its links alone: its owner wires them one at a time, and a poll that lands in
# the middle must not delete half an insert. The grace timer above is what
# eventually lets a half-wired host be pruned as a stray.
host_endpoint() {
  local node=${1%%:*}
  [[ ${node,,} == *carla* ]]
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
    ((host_guard)) && host_endpoint "$src" && continue
    del "$src" "$1"
  done < <(sources_to "$1")
}

prune_dests() { # $1 = output port, $2 = the only destination it should have ("" for none)
  local dst
  while IFS= read -r dst; do
    [[ -z $dst || $dst == "$2" ]] && continue
    ((host_guard)) && host_endpoint "$dst" && continue
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

# --- the insert's lifetime -------------------------------------------------
#
# The DSP unit is not started at login: this loop starts it while the speaker
# output is in use and stops it when it is not, so an idle machine has no
# real-time client in the graph and no insert for a config reload to break.
#
# "In use" is the rule the headphone router shares: the sink is the default
# output, or an app plays to it. Being the default is what lets playback start
# with the DSP already in the path — starting the insert only when the first
# sample arrives would leak the first fraction of a second past it.
UNIT=camilladsp

unit_active() { "$systemctl" --user is-active --quiet "$UNIT" 2> /dev/null; }

default_sink() {
  "$pwMeta" -n default 2> /dev/null | "$awk" -F'"' '/default\.audio\.sink/ { print $4; exit }'
}

# An app playing into the sink. The loopbacks' own streams are plumbing and are
# not a reason to keep the DSP running.
app_streams() {
  local src
  while IFS= read -r src; do
    [[ -z $src || $src == playback.* || $src == camilladsp-* ]] && continue
    return 0
  done < <(sources_to "game-stereo:playback_FL")
  return 1
}

armed() {
  [[ $(default_sink) == "game-stereo" ]] && return 0
  app_streams
}

# The four links the insert is, both ways, and nothing else on the DSP ports or
# on the monitor stream. The last two matter: WirePlumber rescans every
# autoconnect stream when a sink appears and links the loopback's playback
# stream into it (measured 2026-11-13: a replugged USB DAC received the
# monitors' mix in parallel with the DSP, and being priority.driver = 1109 it
# also took the graph clock from the RME, whose capture then xran every few
# seconds).
route_complete() {
  has_link "$GAME:output_FL" "$CAP:input_FL" \
    && has_link "$GAME:output_FR" "$CAP:input_FR" \
    && has_link "$PB:output_FL" "$AES_L" \
    && has_link "$PB:output_FR" "$AES_R" \
    && ! has_link "$GAME:output_FL" "$AES_L" \
    && ! has_link "$GAME:output_FR" "$AES_R" \
    && ! has_link "$GAME:output_FL" "$STRAY_L" \
    && ! has_link "$GAME:output_FR" "$STRAY_R" \
    && ! has_link "$GAME:output_FL" "$AES_R" \
    && ! has_link "$GAME:output_FR" "$AES_L" \
    && only_sources "$CAP:input_FL" "$GAME:output_FL" \
    && only_sources "$CAP:input_FR" "$GAME:output_FR" \
    && only_dests "$GAME:output_FL" "$CAP:input_FL" \
    && only_dests "$GAME:output_FR" "$CAP:input_FR" \
    && only_dests "$PB:output_FL" "$AES_L" \
    && only_dests "$PB:output_FR" "$AES_R"
}

# Add first, prune after: when a port vanished between the check and the call,
# the working path is still there instead of having been taken down already.
#
# Order matters for the first two groups: WirePlumber auto-links a new stream
# to the default sink (game-stereo), whose monitor is this capture input.
# Connecting GAME -> CAP while the playback stream still feeds game-stereo
# closes a unity-gain feedback loop, and each prune is a pw-link round trip
# (slow under load). Move the playback stream to AES, prune the stray link,
# and only then close the capture path.
route_dsp() {
  add "$PB:output_FL" "$AES_L"
  add "$PB:output_FR" "$AES_R"
  prune_dests "$PB:output_FL" "$AES_L"
  prune_dests "$PB:output_FR" "$AES_R"
  add "$GAME:output_FL" "$CAP:input_FL"
  add "$GAME:output_FR" "$CAP:input_FR"
  prune_sources "$CAP:input_FL" "$GAME:output_FL"
  prune_sources "$CAP:input_FR" "$GAME:output_FR"
  # A second destination on the monitor stream is WirePlumber's stray link into
  # a sink that just appeared, not a route: the speakers' audio must not play
  # anywhere but through the insert.
  prune_dests "$GAME:output_FL" "$CAP:input_FL"
  prune_dests "$GAME:output_FR" "$CAP:input_FR"
  # Exactly one path to AES: the DSP's.
  del "$GAME:output_FL" "$AES_L"
  del "$GAME:output_FR" "$AES_R"
  del "$GAME:output_FL" "$STRAY_L"
  del "$GAME:output_FR" "$STRAY_R"
  # A crossed stray (the left channel into the right AES pair) was seen once,
  # when WirePlumber picked the free port next to a busy one; both directions
  # go, because a crossed pair is never the intended route.
  del "$GAME:output_FL" "$AES_R"
  del "$GAME:output_FR" "$AES_L"
}

route_direct() {
  add "$GAME:output_FL" "$AES_L"
  add "$GAME:output_FR" "$AES_R"
  prune_dests "$GAME:output_FL" "$AES_L"
  prune_dests "$GAME:output_FR" "$AES_R"
  del "$GAME:output_FL" "$STRAY_L"
  del "$GAME:output_FR" "$STRAY_R"
  del "$GAME:output_FL" "$AES_R"
  del "$GAME:output_FR" "$AES_L"
}

# The host insert. A crosspoint can carry a chain of VST effects through a
# headless host (`pw-jack carla --no-gui`); on the managed path that host is a
# third node — game-stereo -> host -> camilladsp-capture, or
# camilladsp-playback -> host -> the RME pair. The router does not start or
# wire it (the matrix tab or the person running the exported project does), but
# it has to accept the hosted four-link path as a steady state instead of
# pruning it as a stray every two seconds.
#
# The host is recognised by its client name and by the four ports a continuous
# rack exposes (audio-in1/2, audio-out1/2). A host that is merely running, or a
# chain on another crosspoint, changes nothing: only links into this path count.
host_node() {
  local port name
  local -A in1=() in2=() out1=() out2=()
  while IFS= read -r port; do
    name=${port%:*}
    [[ ${name,,} == *carla* ]] || continue
    case ${port##*:} in
      audio-in1) in1[$name]=1 ;;
      audio-in2) in2[$name]=1 ;;
      audio-out1) out1[$name]=1 ;;
      audio-out2) out2[$name]=1 ;;
    esac
  done < <(
    "$pwLink" -i 2> /dev/null
    "$pwLink" -o 2> /dev/null
  )
  for name in "${!in1[@]}"; do
    [[ -n ${in2[$name]-} && -n ${out1[$name]-} && -n ${out2[$name]-} ]] || continue
    printf '%s\n' "$name"
    return 0
  done
  return 1
}

host_capture_wired() { # $1 = host node; the capture half goes through it
  has_link "$GAME:output_FL" "$1:audio-in1" \
    && has_link "$GAME:output_FR" "$1:audio-in2" \
    && has_link "$1:audio-out1" "$CAP:input_FL" \
    && has_link "$1:audio-out2" "$CAP:input_FR"
}

host_playback_wired() { # $1 = host node; the playback half goes through it
  has_link "$PB:output_FL" "$1:audio-in1" \
    && has_link "$PB:output_FR" "$1:audio-in2" \
    && has_link "$1:audio-out1" "$AES_L" \
    && has_link "$1:audio-out2" "$AES_R"
}

host_touched() { # $1 = host node; any one of the links a host insert makes
  has_link "$GAME:output_FL" "$1:audio-in1" \
    || has_link "$GAME:output_FR" "$1:audio-in2" \
    || has_link "$1:audio-out1" "$CAP:input_FL" \
    || has_link "$1:audio-out2" "$CAP:input_FR" \
    || has_link "$PB:output_FL" "$1:audio-in1" \
    || has_link "$PB:output_FR" "$1:audio-in2" \
    || has_link "$1:audio-out1" "$AES_L" \
    || has_link "$1:audio-out2" "$AES_R"
}

host_capture_complete() { # $1 = host node
  host_capture_wired "$1" \
    && has_link "$PB:output_FL" "$AES_L" \
    && has_link "$PB:output_FR" "$AES_R" \
    && ! has_link "$GAME:output_FL" "$CAP:input_FL" \
    && ! has_link "$GAME:output_FR" "$CAP:input_FR" \
    && ! has_link "$GAME:output_FL" "$AES_L" \
    && ! has_link "$GAME:output_FR" "$AES_R" \
    && only_sources "$CAP:input_FL" "$1:audio-out1" \
    && only_sources "$CAP:input_FR" "$1:audio-out2" \
    && only_dests "$GAME:output_FL" "$1:audio-in1" \
    && only_dests "$GAME:output_FR" "$1:audio-in2" \
    && only_dests "$PB:output_FL" "$AES_L" \
    && only_dests "$PB:output_FR" "$AES_R" \
    && ! has_link "$1:audio-out1" "$AES_L" \
    && ! has_link "$1:audio-out2" "$AES_R"
}

host_playback_complete() { # $1 = host node
  host_playback_wired "$1" \
    && has_link "$GAME:output_FL" "$CAP:input_FL" \
    && has_link "$GAME:output_FR" "$CAP:input_FR" \
    && ! has_link "$PB:output_FL" "$AES_L" \
    && ! has_link "$PB:output_FR" "$AES_R" \
    && only_sources "$CAP:input_FL" "$GAME:output_FL" \
    && only_sources "$CAP:input_FR" "$GAME:output_FR" \
    && only_dests "$GAME:output_FL" "$CAP:input_FL" \
    && only_dests "$GAME:output_FR" "$CAP:input_FR" \
    && only_dests "$PB:output_FL" "$1:audio-in1" \
    && only_dests "$PB:output_FR" "$1:audio-in2" \
    && ! has_link "$GAME:output_FL" "$1:audio-in1" \
    && ! has_link "$GAME:output_FR" "$1:audio-in2"
}

# Same order as route_dsp: add what carries sound first, take the direct cable
# down last. The host links are already there when this runs — its owner made
# them — but adding them again is free and makes a repair possible.
route_host_capture() { # $1 = host node
  add "$PB:output_FL" "$AES_L"
  add "$PB:output_FR" "$AES_R"
  prune_dests "$PB:output_FL" "$AES_L"
  prune_dests "$PB:output_FR" "$AES_R"
  add "$GAME:output_FL" "$1:audio-in1"
  add "$GAME:output_FR" "$1:audio-in2"
  add "$1:audio-out1" "$CAP:input_FL"
  add "$1:audio-out2" "$CAP:input_FR"
  prune_sources "$CAP:input_FL" "$1:audio-out1"
  prune_sources "$CAP:input_FR" "$1:audio-out2"
  prune_dests "$GAME:output_FL" "$1:audio-in1"
  prune_dests "$GAME:output_FR" "$1:audio-in2"
  del "$GAME:output_FL" "$CAP:input_FL"
  del "$GAME:output_FR" "$CAP:input_FR"
  del "$GAME:output_FL" "$AES_L"
  del "$GAME:output_FR" "$AES_R"
  del "$1:audio-out1" "$AES_L"
  del "$1:audio-out2" "$AES_R"
  del "$GAME:output_FL" "$STRAY_L"
  del "$GAME:output_FR" "$STRAY_R"
}

route_host_playback() { # $1 = host node
  add "$GAME:output_FL" "$CAP:input_FL"
  add "$GAME:output_FR" "$CAP:input_FR"
  prune_sources "$CAP:input_FL" "$GAME:output_FL"
  prune_sources "$CAP:input_FR" "$GAME:output_FR"
  prune_dests "$GAME:output_FL" "$CAP:input_FL"
  prune_dests "$GAME:output_FR" "$CAP:input_FR"
  add "$PB:output_FL" "$1:audio-in1"
  add "$PB:output_FR" "$1:audio-in2"
  add "$1:audio-out1" "$AES_L"
  add "$1:audio-out2" "$AES_R"
  prune_dests "$PB:output_FL" "$1:audio-in1"
  prune_dests "$PB:output_FR" "$1:audio-in2"
  del "$GAME:output_FL" "$1:audio-in1"
  del "$GAME:output_FR" "$1:audio-in2"
  del "$GAME:output_FL" "$AES_L"
  del "$GAME:output_FR" "$AES_R"
  del "$GAME:output_FL" "$STRAY_L"
  del "$GAME:output_FR" "$STRAY_R"
}

while :; do
  # Lifetime first: with the unit down this loop is the direct path, with it up
  # the state machine below owns the wiring.
  if armed; then
    idle=0
    if ! unit_active; then
      now=$("$date" +%s)
      if ((now - last_start >= 2)); then
        last_start=$now
        "$systemctl" --user start "$UNIT" > /dev/null 2>&1 || log "could not start $UNIT"
        # Re-poll quickly so the insert is wired as soon as the nodes exist.
        "$sleep" 0.2
        continue
      fi
    fi
  else
    if unit_active; then
      ((idle++))
      if ((idle >= 3)); then
        # Another output is default and nothing plays here: take the direct
        # path down first, then stop the unit, so no audio is cut on exit.
        if [[ $state == dsp ]]; then
          route_direct
          state=direct
          log "route: direct (idle)"
        fi
        "$systemctl" --user stop "$UNIT" > /dev/null 2>&1 || true
        idle=0
      fi
    else
      idle=0
    fi
  fi

  # Mirror of the headphone router's prune: WirePlumber can link the headphone
  # loopback's stream into game-stereo, which would put headphone audio on the
  # monitors.
  del "playback.headphones:output_FL" "game-stereo:playback_FL"
  del "playback.headphones:output_FR" "game-stereo:playback_FR"

  # Nothing can be routed while one of the two ends is absent. While that lasts,
  # a live DSP stream is also taken off every sink it has: with its AES target
  # gone, WirePlumber's own re-link would feed the playback stream into
  # game-stereo, which is the input of the capture stream — a loop.
  if ! port_exists "$GAME:output_FL" || ! port_exists "$AES_L"; then
    if dsp_up; then
      prune_dests "$PB:output_FL" ""
      prune_dests "$PB:output_FR" ""
    fi
    host_grace=0
    say_once waiting "route: waiting for game-stereo and the RME AES pair"
    "$sleep" 2
    continue
  fi
  # A host that is only running changes nothing; one with a link into this path
  # is either a finished insert or one being wired.
  host=
  host_guard=0
  if dsp_up; then
    host=$(host_node) || true
  fi
  hosted_capture=
  hosted_playback=
  if [[ -n $host ]]; then
    host_guard=1
    host_capture_wired "$host" && hosted_capture=1
    host_playback_wired "$host" && hosted_playback=1
  fi

  # The two host cells are wired one at a time, and the direct cable may already
  # be gone. Hold repairs for a few polls instead of deleting a half-made
  # insert; after that it is a stray link like any other.
  if [[ $state != hostcap && $state != hostplay ]] \
    && [[ -n $host && -z $hosted_capture && -z $hosted_playback ]] \
    && host_touched "$host"; then
    if ((host_grace < 5)); then
      ((host_grace++))
      say_once host "route: waiting for the host insert to settle"
      "$sleep" 2
      continue
    fi
    host_guard=0
  else
    host_grace=0
  fi

  said=
  if [[ -n $hosted_capture ]]; then
    want=hostcap
  elif [[ -n $hosted_playback ]]; then
    want=hostplay
  elif [[ -n $host && $state == hostcap ]] && host_touched "$host"; then
    # One host link dropped while the insert was live: repair it rather than
    # treating the leftovers as a fresh, half-wired insert.
    want=hostcap
  elif [[ -n $host && $state == hostplay ]] && host_touched "$host"; then
    want=hostplay
  elif dsp_up; then
    want=dsp
  else
    want=direct
  fi

  if [[ $want != $state ]]; then
    case $want in
      dsp) route_dsp ;;
      direct) route_direct ;;
      hostcap) route_host_capture "$host" ;;
      hostplay) route_host_playback "$host" ;;
    esac
    log "route: $want"
    state=$want
  else
    case $want in
      dsp)
        route_complete || {
          # The owner may have wired the host between the check above and this
          # repair. Re-read once: a half-made insert is the next poll's problem,
          # not a stray link to delete.
          late_host=$(host_node) || true
          if [[ -n $late_host ]] && host_touched "$late_host" && ((host_grace < 5)); then
            host_guard=1
          else
            route_dsp
            log "route: repaired"
          fi
        }
        ;;
      direct)
        has_link "$GAME:output_FL" "$AES_L" \
          && has_link "$GAME:output_FR" "$AES_R" \
          && only_dests "$GAME:output_FL" "$AES_L" \
          && only_dests "$GAME:output_FR" "$AES_R" \
          && ! has_link "$GAME:output_FL" "$STRAY_L" \
          && ! has_link "$GAME:output_FR" "$STRAY_R" \
          && ! has_link "$GAME:output_FL" "$AES_R" \
          && ! has_link "$GAME:output_FR" "$AES_L" \
          || {
            route_direct
            log "route: repaired (direct)"
          }
        ;;
      hostcap)
        host_capture_complete "$host" || {
          route_host_capture "$host"
          log "route: repaired (host capture)"
        }
        ;;
      hostplay)
        host_playback_complete "$host" || {
          route_host_playback "$host"
          log "route: repaired (host playback)"
        }
        ;;
    esac
  fi
  "$sleep" 2
done
