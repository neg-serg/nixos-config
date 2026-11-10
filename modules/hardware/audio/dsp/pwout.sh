# pwout — choose the default output: the monitors or the headphones.
#
#     pwout               what is selected now, and whether the DSP runs for it
#     pwout speakers      default sink -> game-stereo (RME AES -> Genelec)
#     pwout headphones    default sink -> headphones (CamillaDSP -> E1DA)
#     pwout dac           list the sinks that look like the headphone DAC
#
# Both outputs are virtual sinks; the DSP instances are lazy (see
# route-headphones.sh and route.sh) and follow this choice: the selected
# output's DSP is left running so playback starts with it already in the path,
# the other one is stopped when its sink has no streams.
#
# `headphones` refuses to become the default while no DAC matches the pattern:
# the sink exists unconditionally, so selecting it with nothing behind it would
# just be a silent output.
set -u

pwDump="@pwLink@/bin/pw-dump"
jq="@jq@/bin/jq"
wpctl="@wpctl@/bin/wpctl"
systemctl="@systemctl@/bin/systemctl"
awk="@awk@/bin/awk"
date="@date@/bin/date"

DAC_MATCH='@dacMatch@'
SPEAKERS=game-stereo
HEADPHONES=headphones

sinks() { # id, name, description — one line each
  "$pwDump" 2> /dev/null | "$jq" -r '
    .[] | select(.type == "PipeWire:Interface:Node")
    | select(.info.props["media.class"] == "Audio/Sink")
    | "\(.id)\t\(.info.props["node.name"] // "")\t\(.info.props["node.description"] // "")"' 2> /dev/null
}

node_id() { # $1 = node.name
  sinks | "$awk" -F'\t' -v n="$1" '
    $2 == n { print $1; exit }
    $3 == n { print $1; exit }'
}

has_sink() {
  [[ -n $(node_id "$1") ]]
}

dac_node() {
  sinks | "$awk" -F'\t' -v m="$DAC_MATCH" 'tolower($2 " " $3) ~ tolower(m) { print $2; exit }'
}

default_sink() {
  "@pwLink@/bin/pw-metadata" -n default 2> /dev/null | "$awk" -F'"' '/default\.audio\.sink/ { print $4; exit }'
}

dsp_state() { # $1 = unit
  if "$systemctl" --user is-active --quiet "$1" 2> /dev/null; then
    echo running
  else
    echo stopped
  fi
}

status() {
  local cur dac
  cur=$(default_sink)
  dac=$(dac_node)
  printf 'default output: %s\n' "${cur:-unknown}"
  printf 'monitors:       %s  (CamillaDSP %s, %s)\n' "$SPEAKERS" "$(dsp_state camilladsp)" \
    "$(has_sink "$SPEAKERS" && echo present || echo missing)"
  printf 'headphones:     %s  (CamillaDSP %s, %s; DAC match %s)\n' "$HEADPHONES" \
    "$(dsp_state camilladsp-headphones)" \
    "$(has_sink "$HEADPHONES" && echo present || echo missing)" "${dac:-none}"
}

set_default() { # $1 = node name
  local id
  id=$(node_id "$1")
  if [[ -z $id ]]; then
    printf 'pwout: no sink named %s\n' "$1" >&2
    return 1
  fi
  "$wpctl" set-default "$id" > /dev/null
  printf 'default output: %s\n' "$1"
}

case ${1:-status} in
  status | '')
    status
    ;;
  speakers)
    set_default "$SPEAKERS"
    ;;
  headphones)
    if [[ -z $(dac_node) ]]; then
      printf 'pwout: no sink matches the DAC pattern %s; is it plugged in?\n' "$DAC_MATCH" >&2
      printf 'pwout: run `pwout dac` to see the sinks that exist\n' >&2
      exit 1
    fi
    set_default "$HEADPHONES"
    ;;
  dac)
    printf 'sinks that match %s:\n' "$DAC_MATCH"
    sinks | "$awk" -F'\t' -v m="$DAC_MATCH" 'tolower($2 " " $3) ~ tolower(m) { printf "  %s. %s — %s\n", $1, $2, $3 }'
    printf 'all sinks:\n'
    sinks | "$awk" -F'\t' '{ printf "  %s. %s — %s\n", $1, $2, $3 }'
    ;;
  *)
    printf 'usage: pwout [status|speakers|headphones|dac]\n' >&2
    exit 2
    ;;
esac
