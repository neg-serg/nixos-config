#!/usr/bin/env zsh
setopt ERR_EXIT NOUNSET PIPE_FAIL
IFS=$'\n\t'

ROUTING_YAML="/etc/audio/routing.yaml"

typeset -A targets
typeset -A labels
typeset -a route_order

init_config() {
  for key_pair_label in "an:0 1:Speakers" "aes:2 3:AES" "spdif:4 5:SPDIF" "phones:6 7:Headphones"; do
    local key="${key_pair_label%%:*}"
    local rest="${key_pair_label#*:}"
    local pair="${rest%:*}"
    local label="${rest##*:}"
    targets[$key]="$pair"
    labels[$key]="$label"
    route_order+=("$key")
  done
}

die() { print -u2 -- "pw-route: $*"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

usage() {
  local route_list=""
  for k in "${route_order[@]}"; do
    route_list+=$(printf '  %-8s -> AUX%s/AUX%s  (%s)\n' "$k" "${targets[$k]%% *}" "${targets[$k]##* }" "${labels[$k]}")
  done
  cat <<EOF
Usage: pw-route <$(echo "${route_order[@]}" | tr ' ' '|')|toggle|current|status|list>

Route active stereo PipeWire streams on the RME AIO Pro pro-audio sink:
${route_list}  toggle  -> quick toggle between output pairs
  current -> print active mirror target
  status  -> show current RME playback links
  list    -> all routes as JSON (for UI consumption)
EOF
}

find_rme_sink() {
  local sink_name
  sink_name="$(pw-cli list-objects Node | awk -v nick="RME AIO Pro" '
    /^id/ { node = "" }
    /node.name/ && /alsa_output/ { node = $3; gsub(/"/, "", node) }
    index($0, "node.nick = \"" nick "\"") && node != "" { print node; exit }
  ')"
  [[ -n "$sink_name" ]] || die "RME AIO Pro sink not found"
  print -- "$sink_name"
}

show_status() {
  local sink_name="$1"
  local link_dump
  link_dump="$(pw-link -l)"
  [[ -n "$link_dump" ]] || die "no PipeWire links found"
  printf '%s\n' "$link_dump" | awk -v sink="$sink_name" '
    $0 ~ sink":playback_AUX" { print; seen=1; next }
    seen && /^  \|<-/ { print; next }
    seen { seen=0 }
  '
}

disconnect_stream_port_links() {
  local stream_port="$1"
  local link_dump
  local -a ports
  link_dump="$(pw-link -l)"
  ports=(
    ${(f)$(printf '%s\n' "$link_dump" | awk -v stream="$stream_port" '
      $0 == stream { seen=1; next }
      seen && /^  \|-> / {
        sub(/^  \|-> /, "")
        print
        next
      }
      seen { seen=0 }
    ')}
  )
  for port in "${ports[@]}"; do
    [[ -n "$port" ]] || continue
    pw-link -d "$stream_port" "$port" 2>/dev/null || true
  done
}

route_monitor_pair() {
  local sink_name="$3"
  local left_aux="$4"
  local right_aux="$5"
  local left_monitor="$1"
  local right_monitor="$2"
  disconnect_stream_port_links "$left_monitor"
  disconnect_stream_port_links "$right_monitor"
  pw-link "$left_monitor" "$sink_name:playback_AUX${left_aux}"
  pw-link "$right_monitor" "$sink_name:playback_AUX${right_aux}"
}

route_target() {
  local target_name="$1"
  local sink_name="$2"
  local -a pair
  pair=( ${(s: :)targets[$target_name]} )
  local left_monitor="$sink_name:monitor_AUX0"
  local right_monitor="$sink_name:monitor_AUX1"
  route_monitor_pair "$left_monitor" "$right_monitor" "$sink_name" "$pair[1]" "$pair[2]"
  print -- "$target_name -> AUX$pair[1]/AUX$pair[2]"
  command -v pactl >/dev/null 2>&1 && pactl set-default-sink "$sink_name" 2>/dev/null || true
}

port_has_link_to() {
  local stream_port="$1"
  local target_port="$2"
  local link_dump="$3"
  printf '%s\n' "$link_dump" | awk -v stream="$stream_port" '
    $0 == stream { seen=1; next }
    seen && /^  \|-> / {
      sub(/^  \|-> /, "")
      print
      next
    }
    seen { seen=0 }
  ' | grep -Fxq -- "$target_port"
}

get_current_target() {
  local sink_name="$1"
  local link_dump
  link_dump="$(pw-link -l)"
  for target_name in "${route_order[@]}"; do
    local -a pair=( ${(s: :)targets[$target_name]} )
    if port_has_link_to "$sink_name:monitor_AUX0" "$sink_name:playback_AUX${pair[1]}" "$link_dump" &&
        port_has_link_to "$sink_name:monitor_AUX1" "$sink_name:playback_AUX${pair[2]}" "$link_dump"; then
      print -- "$target_name"
      return
    fi
  done
  print -- "unknown"
}

toggle_target() {
  local sink_name="$1"
  local current_target
  current_target="$(get_current_target "$sink_name")"
  if [[ "$current_target" == "$route_order[2]" ]]; then
    next_target="$route_order[1]"
  else
    next_target="$route_order[2]"
  fi
  route_target "$next_target" "$sink_name"
}

list_routes() {
  print -n "["
  local first=1
  for k in "${route_order[@]}"; do
    (( first )) || print -n ","
    first=0
    local -a pair=( ${(s: :)targets[$k]} )
    print -n "{\"key\":\"$k\",\"label\":\"${labels[$k]}\",\"left\":$pair[1],\"right\":$pair[2]}"
  done
  print "]"
}

main() {
  local command="${1:-}"
  local sink_name
  init_config
  local -a valid_cmds=( toggle current status list -h --help help )
  valid_cmds+=( "${route_order[@]}" )
  if [[ -z "$command" ]] || [[ -z "${valid_cmds[(r)$command]}" ]]; then
    usage >&2
    exit 1
  fi
  need pw-link
  need pw-cli
  sink_name="$(find_rme_sink)"
  case "$command" in
    status)    show_status "$sink_name" ;;
    current)   get_current_target "$sink_name" ;;
    toggle)    toggle_target "$sink_name" ;;
    list)      list_routes ;;
    help|--help|-h) usage ;;
    *)         route_target "$command" "$sink_name" ;;
  esac
}

main "$@"
