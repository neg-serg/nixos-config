# Keep the headphone insert wired: headphones -> DSP -> E1DA, or direct.
#
# The second CamillaDSP instance (`headphones.yml`, port 1235) is not a
# always-on service: this loop owns its lifetime, the way route.sh owns the
# speaker insert's wiring. The rule is the one the user picked: an output's DSP
# is "in use" while that output is the default sink, or while an app plays to
# it. While neither holds, the unit is stopped and the sink is linked straight
# to the DAC, so there is no DSP process to xrun under load and no insert that a
# config reload can break.
#
# Three states, recomputed every poll and repaired only when the exact link set
# is wrong (the same shape as route.sh):
#
#   dsp     headphones -> camilladsp-hp-capture, camilladsp-hp-playback -> E1DA
#   direct  headphones -> E1DA (the DSP is stopped or still starting)
#   off     no DAC: the sink keeps existing, but nothing can be routed
#
# The DAC is found by a case-insensitive regex over node name/description
# (`dacMatch` from the module), because a USB device's node name carries its
# serial and path and changes when it is replugged.
#
# A `headphones`-default output with no DAC would be silent; the loop hands the
# default back to the speakers in that case rather than leaving a dead output
# selected. The unit is stopped first, so no audio is cut mid-stream: the state
# is only ever changed while nothing is armed.
set -u

pwLink="@pwLink@/bin/pw-link"
pwDump="@pwLink@/bin/pw-dump"
pwMeta="@pwLink@/bin/pw-metadata"
jq="@jq@/bin/jq"
awk="@awk@/bin/awk"
grep="@grep@/bin/grep"
sleep="@sleep@/bin/sleep"
date="@date@/bin/date"
systemctl="@systemctl@/bin/systemctl"
wpctl="@wpctl@/bin/wpctl"

UNIT=camilladsp-headphones
SINK=headphones
PB=playback.headphones
CAP=camilladsp-hp-capture
HPB=camilladsp-hp-playback
GAME=playback.game-stereo
DAC_MATCH='@dacMatch@'
# The loopbacks' own streams are plumbing, not apps: WirePlumber has been seen
# linking them into sinks that appeared later, and neither the arming rule nor
# the routing may treat them as a reason to play.
FOREIGN=(playback.game-stereo playback.headphones camilladsp-hp-playback)

state=off
idle=0
said=
dac=
dac_idle=0

log() { printf '%s route-headphones: %s\n' "$("$date" '+%F %T')" "$*"; }

say_once() {
  [[ $said == "$1" ]] && return 0
  said=$1
  log "$2"
}

# Links as `pw-link -l` prints them: a bare "node:port" header, then one indented
# "|<-" / "|->" line per link.
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

port_exists() { # $1 = node:port
  "$pwLink" -i 2> /dev/null | "$grep" -qxF "$1" \
    || "$pwLink" -o 2> /dev/null | "$grep" -qxF "$1"
}

add() { "$pwLink" "$1" "$2" 2> /dev/null || true; }
del() { "$pwLink" -d "$1" "$2" 2> /dev/null || true; }

prune_sources() { # $1 = destination port, $2 = the only source it should have
  local src
  while IFS= read -r src; do
    [[ -z $src || $src == "$2" ]] && continue
    del "$src" "$1"
  done < <(sources_to "$1")
}

prune_dests() { # $1 = source port, $2 = the only destination it should have
  local dst
  while IFS= read -r dst; do
    [[ -z $dst || $dst == "$2" ]] && continue
    del "$1" "$dst"
  done < <(dests_of "$1")
}

only_dests() { # $1 = source port, $2 = the wanted destination
  local dst n=0
  while IFS= read -r dst; do
    [[ -z $dst ]] && continue
    ((n++))
    [[ $dst == "$2" ]] || return 1
  done < <(dests_of "$1")
  ((n == 1))
}

only_sources() { # $1 = destination port, $2 = the wanted source
  local src n=0
  while IFS= read -r src; do
    [[ -z $src ]] && continue
    ((n++))
    [[ $src == "$2" ]] || return 1
  done < <(sources_to "$1")
  ((n == 1))
}

# The node whose name or description matches the DAC pattern. `pw-dump` is the
# only listing that carries both properties for every node, and jq is the parser
# that does not depend on the text layout pw-cli prints.
dac_node() {
  "$pwDump" 2> /dev/null | "$jq" -r --arg m "$DAC_MATCH" '
    .[]
    | select(.type == "PipeWire:Interface:Node")
    | select(.info.props["media.class"] == "Audio/Sink")
    | select(("\(.info.props["node.name"] // "") \(.info.props["node.description"] // "")")
             | test($m; "i"))
    | select((.info.props["node.name"] // "") != "headphones"
             and (.info.props["node.name"] // "") != "game-stereo")
    | .info.props["node.name"]' 2> /dev/null | head -n1
}

node_id() { # $1 = node.name
  "$pwDump" 2> /dev/null | "$jq" -r --arg n "$1" '
    .[] | select(.type == "PipeWire:Interface:Node")
    | select(.info.props["node.name"] == $n) | .id' 2> /dev/null | head -n1
}

default_sink() {
  "$pwMeta" -n default 2> /dev/null | "$awk" -F'"' '/default\.audio\.sink/ { print $4; exit }'
}

unit_active() {
  "$systemctl" --user is-active --quiet "$UNIT" 2> /dev/null
}

# An app playing to the sink. The loopbacks' own streams are filtered out: they
# are plumbing, and WirePlumber links them into new sinks on its own.
app_streams() {
  local src f
  while IFS= read -r src; do
    [[ -z $src ]] && continue
    for f in "${FOREIGN[@]}"; do
      [[ $src == "$f":* ]] && continue 2
    done
    return 0
  done < <(sources_to "$SINK:playback_FL")
  return 1
}

armed() {
  [[ $(default_sink) == "$SINK" ]] && return 0
  app_streams
}

dsp_up() {
  port_exists "$CAP:input_FL" && port_exists "$HPB:output_FL"
}

wired_dsp() {
  has_link "$PB:output_FL" "$CAP:input_FL" \
    && has_link "$PB:output_FR" "$CAP:input_FR" \
    && has_link "$HPB:output_FL" "$dac:playback_FL" \
    && has_link "$HPB:output_FR" "$dac:playback_FR" \
    && only_sources "$CAP:input_FL" "$PB:output_FL" \
    && only_sources "$CAP:input_FR" "$PB:output_FR" \
    && only_dests "$HPB:output_FL" "$dac:playback_FL" \
    && only_dests "$HPB:output_FR" "$dac:playback_FR" \
    && only_dests "$PB:output_FL" "$CAP:input_FL" \
    && only_dests "$PB:output_FR" "$CAP:input_FR"
}

wired_direct() {
  has_link "$PB:output_FL" "$dac:playback_FL" \
    && has_link "$PB:output_FR" "$dac:playback_FR" \
    && only_dests "$PB:output_FL" "$dac:playback_FL" \
    && only_dests "$PB:output_FR" "$dac:playback_FR"
}

route_dsp() {
  # Add the DSP output before taking the direct path down: a gap is worse than
  # a few milliseconds of doubled signal when the DAC is real.
  add "$HPB:output_FL" "$dac:playback_FL"
  add "$HPB:output_FR" "$dac:playback_FR"
  add "$PB:output_FL" "$CAP:input_FL"
  add "$PB:output_FR" "$CAP:input_FR"
  del "$PB:output_FL" "$dac:playback_FL"
  del "$PB:output_FR" "$dac:playback_FR"
  prune_sources "$CAP:input_FL" "$PB:output_FL"
  prune_sources "$CAP:input_FR" "$PB:output_FR"
  prune_dests "$HPB:output_FL" "$dac:playback_FL"
  prune_dests "$HPB:output_FR" "$dac:playback_FR"
  prune_dests "$PB:output_FL" "$CAP:input_FL"
  prune_dests "$PB:output_FR" "$CAP:input_FR"
}

route_direct() {
  add "$PB:output_FL" "$dac:playback_FL"
  add "$PB:output_FR" "$dac:playback_FR"
  prune_dests "$PB:output_FL" "$dac:playback_FL"
  prune_dests "$PB:output_FR" "$dac:playback_FR"
  prune_dests "$HPB:output_FL" ""
  prune_dests "$HPB:output_FR" ""
}

# No DAC: take the sink off every destination, and do not leave it selected.
route_off() {
  prune_dests "$PB:output_FL" ""
  prune_dests "$PB:output_FR" ""
  prune_dests "$HPB:output_FL" ""
  prune_dests "$HPB:output_FR" ""
}

last_start=0

while :; do
  dac=$(dac_node) || true

  # WirePlumber links loopback streams into sinks that appear after them
  # (measured 2026-11-10: the speaker loopback's stream landed in this sink's
  # input), which would put the monitors' audio on the headphones. The speaker
  # router prunes the mirror-image link.
  del "$GAME:output_FL" "$SINK:playback_FL"
  del "$GAME:output_FR" "$SINK:playback_FR"

  # The chosen output must not be a dead end: give it back to the speakers when
  # the DAC it needs is gone. The check runs before routing, so the direct path
  # for the speakers is already the router's business.
  if [[ -z $dac && $(default_sink) == "$SINK" ]]; then
    speakers=$(node_id game-stereo) || true
    if [[ -n ${speakers:-} ]]; then
      "$wpctl" set-default "$speakers" > /dev/null 2>&1 || true
      say_once nodac "no DAC matching '$DAC_MATCH': default handed back to game-stereo"
      "$sleep" 2
      continue
    fi
  fi

  if armed; then
    idle=0
    if ! unit_active; then
      # Rate-limit the start: a unit that keeps failing to come up must not
      # turn the loop into a systemctl spinner.
      now=$("$date" +%s)
      if ((now - last_start >= 2)); then
        last_start=$now
        "$systemctl" --user start "$UNIT" > /dev/null 2>&1 \
          || log "could not start $UNIT"
        # Re-poll quickly: the insert should be wired as soon as the nodes
        # exist, not up to two seconds later.
        "$sleep" 0.2
        continue
      fi
    fi
  else
    if unit_active; then
      ((idle++))
      if ((idle >= 3)); then
        # Nothing is playing: take the direct path first, then stop the unit.
        [[ $state == dsp && -n $dac ]] && route_direct
        "$systemctl" --user stop "$UNIT" > /dev/null 2>&1 || true
        state=off
        idle=0
        log "dsp stopped (not in use)"
      fi
    else
      idle=0
    fi
  fi

  if [[ -z $dac ]]; then
    [[ $state != off ]] && {
      route_off
      state=off
    }
    say_once nodac2 "no DAC matching '$DAC_MATCH': headphones are silent"
  elif dsp_up; then
    if [[ $state != dsp || ! wired_dsp ]]; then
      route_dsp
      state=dsp
      say_once dsp "dsp: headphones -> $UNIT -> $dac"
    fi
  else
    # The unit is stopped, starting, or reloading: keep the direct path alive.
    if [[ $state != direct || ! wired_direct ]]; then
      route_direct
      state=direct
      say_once direct "direct: headphones -> $dac (DSP not running)"
    fi
  fi
  "$sleep" 2
done
