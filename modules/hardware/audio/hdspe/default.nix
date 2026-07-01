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
        ${pwRouteScript}/bin/pw-route aes || true
        exit 0
      fi
      sleep 0.5
    done
    exit 0
  '';

  # pw-route: switch RME AIO Pro output between an/aes/spdif/phones
  pwRouteScript = pkgs.writeScriptBin "pw-route" (builtins.readFile ./pw-route.sh);

  # routing config for pw-route
  routingYaml = pkgs.writeText "routing.yaml" ''
    ---
    rme:
      nick: "RME AIO Pro"
      card_name: "RME AIO Pro"
      profile: "pro-audio"
      routes:
        aes:
          left: 2
          right: 3
          label: "AES"
        an:
          left: 0
          right: 1
          label: "Speakers"
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
