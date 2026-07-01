{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.hardware.audio.hdspe or { };

  # Set HDSPe hardware mixer levels for ALL output channels at unity gain.
  # The snd-hdspe driver initializes the mixer to all zeros (silent),
  # so we need to set "Chn N" controls to 64 (unity) for audio to pass.
  hdspeMixerScript = pkgs.writeShellScript "hdspe-init-mixer" ''
    set -euo pipefail
    amixer_bin=${pkgs.alsa-utils}/bin/amixer

    # Find HDSPe card
    found=""
    for card in "RMEAIO" "HDSPeAIO" "HDSPe" "AIO" "RME_AIO" "HDSPe24048964"; do
      if $amixer_bin -c "$card" info >/dev/null 2>&1; then
        found="$card"
        break
      fi
    done
    if [ -z "$found" ]; then
      # Fallback: scan all cards for HDSPe
      for card in $($amixer_bin cards 2>/dev/null | grep -ioE 'card[0-9]+|HDSPe[0-9]+' | tr -d ','); do
        if $amixer_bin -c "$card" info 2>/dev/null | grep -qi "HDSPe\|RME.*AIO"; then
          found="$card"
          break
        fi
      done
    fi

    [ -n "$found" ] || exit 0

    # Set all Chn N controls to unity gain (64)
    # AIO Pro has up to 16 output channels at single speed
    for chn in $(seq 1 16); do
      $amixer_bin -c "$found" set "Chn $chn" 64 >/dev/null 2>&1 || true
    done
  '';

  # Set HDSPe pro-audio output as default PipeWire sink
  hdspeDefaultScript = pkgs.writeShellScript "wpctl-set-hdspe-default" ''
    set -euo pipefail
    jq_bin=${pkgs.jq}/bin/jq
    pw_dump_bin=${pkgs.pipewire}/bin/pw-dump
    wpctl_bin=${pkgs.pipewire}/bin/wpctl
    tries=60
    for i in $(seq 1 "$tries"); do
      dump="$("$pw_dump_bin" || true)"
      if [ -z "$dump" ]; then
        sleep 0.5
        continue
      fi
      sink_id="$("$jq_bin" -r '
        .[] | select(
          .type=="PipeWire:Interface:Node"
          and (
            (.info.props["node.nick"] // "") | test("RME AIO Pro"; "i")
            or (.info.props["node.name"] // "") | test("hdspe|HDSPe|rme.*aio|rme.*hdsp"; "i")
            or (.info.props["alsa.card_name"] // "") | test("HDSPe|AIO|RME"; "i")
          )
          and (.info.props["media.class"] == "Audio/Sink")
        ) | .id
      ' <<<"$dump" | head -n1 | tr -d '\n')"
      if [ -n "$sink_id" ]; then
        "$wpctl_bin" set-default "$sink_id" || true
        exit 0
      fi
      sleep 0.5
    done
    exit 0
  '';

  # pw-route: switch RME AIO Pro output between an/aes/spdif/phones
  pwRouteScript = pkgs.writeShellScriptBin "pw-route" ''
    #!/usr/bin/env zsh
    setopt ERR_EXIT NOUNSET PIPE_FAIL
    IFS=$'\n\t'

    ROUTING_YAML="/etc/audio/routing.yaml"

    typeset -A targets
    typeset -A labels
    typeset -a route_order

    init_config() {
      for key_pair_label in "an:0 1:Speakers" "aes:2 3:AES" "spdif:4 5:SPDIF" "phones:6 7:Headphones"; do
        local key="$${key_pair_label%%:*}"
        local rest="$${key_pair_label#*:}"
        local pair="$${rest%:*}"
        local label="$${rest##*:}"
        targets[$key]="$pair"
        labels[$key]="$label"
        route_order+=("$key")
      done
    }

    die() { print -u2 -- "pw-route: $*"; exit 1; }
    need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

    usage() {
      local route_list=""
      for k in "$${route_order[@]}"; do
        route_list+=$(printf '  %-8s -> AUX%s/AUX%s  (%s)\n' "$k" "$${targets[$k]%% *}" "$${targets[$k]##* }" "$${labels[$k]}")
      done
      cat <<EOF
    Usage: pw-route <$(echo "$${route_order[@]}" | tr ' ' '|')|toggle|current|status|list>

    Route active stereo PipeWire streams on the RME AIO Pro pro-audio sink:
    $${route_list}  toggle  -> quick toggle between output pairs
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
        $${(f)$(printf '%s\n' "$link_dump" | awk -v stream="$stream_port" '
          $0 == stream { seen=1; next }
          seen && /^  \|-> / {
            sub(/^  \|-> /, "")
            print
            next
          }
          seen { seen=0 }
        ')}
      )
      for port in "$${ports[@]}"; do
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
      pw-link "$left_monitor" "$sink_name:playback_AUX$${left_aux}"
      pw-link "$right_monitor" "$sink_name:playback_AUX$${right_aux}"
    }

    route_target() {
      local target_name="$1"
      local sink_name="$2"
      local -a pair
      pair=( $${(s: :)targets[$target_name]} )
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
      for target_name in "$${route_order[@]}"; do
        local -a pair=( $${(s: :)targets[$target_name]} )
        if port_has_link_to "$sink_name:monitor_AUX0" "$sink_name:playback_AUX$${pair[1]}" "$link_dump" &&
            port_has_link_to "$sink_name:monitor_AUX1" "$sink_name:playback_AUX$${pair[2]}" "$link_dump"; then
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
      for k in "$${route_order[@]}"; do
        (( first )) || print -n ","
        first=0
        local -a pair=( $${(s: :)targets[$k]} )
        print -n "{\"key\":\"$k\",\"label\":\"$${labels[$k]}\",\"left\":$pair[1],\"right\":$pair[2]}"
      done
      print "]"
    }

    main() {
      local command="$${1:-}"
      local sink_name
      init_config
      local -a valid_cmds=( toggle current status list -h --help help )
      valid_cmds+=( "$${route_order[@]}" )
      if [[ -z "$${valid_cmds[(r)$command]}" ]]; then
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
  '';

  # routing config for pw-route
  routingYaml = pkgs.writeText "routing.yaml" ''
    ---
    rme:
      nick: "RME AIO Pro"
      card_name: "RME AIO Pro"
      profile: "pro-audio"
      routes:
        an:
          left: 0
          right: 1
          label: "Speakers"
        aes:
          left: 2
          right: 3
          label: "AES"
        spdif:
          left: 4
          right: 5
          label: "SPDIF"
        phones:
          left: 6
          right: 7
          label: "Headphones"
  '';
in
{
  options.hardware.audio.hdspe = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable RME HDSPe support (mixer init, default PipeWire sink, pw-route).";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install pw-route script
    environment.systemPackages = [ pwRouteScript pkgs.zsh ];

    # Symlink routing.yaml for pw-route
    environment.etc."audio/routing.yaml".source = routingYaml;

    # System-level: initialize HDSPe hardware mixer on boot
    systemd.services."hdspe-init-mixer" = {
      description = "Initialize RME HDSPe hardware mixer levels";
      after = [ "alsa-store.service" "sound.target" ];
      wantedBy = [ "sound.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${hdspeMixerScript}";
      };
    };

    # User-level: set HDSPe pro-audio sink as default
    systemd.user.services."wp-hdspe-default" = {
      description = "Set RME HDSPe as default PipeWire sink";
      after = [
        "wireplumber.service"
        "pipewire.service"
      ];
      partOf = [ "wireplumber.service" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${hdspeDefaultScript}";
      };
    };
  };
}
