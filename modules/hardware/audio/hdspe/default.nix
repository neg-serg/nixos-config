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
  # NOTE: uses bare command names (amixer/wpctl/pw-link/sed) — PATH is
  # set by the systemd service config below via config.services.pipewire.package.
  hdspeDefaultScript = pkgs.writeShellScript "wpctl-set-hdspe-default" ''
    set -euo pipefail

    # Check if HDSPe card is present first — avoid waiting if hardware absent
    found=""
    for card in "RMEAIO" "HDSPeAIO" "HDSPe" "AIO" "RME_AIO" "HDSPe24048964"; do
      if amixer -c "$card" info >/dev/null 2>&1; then
        found="$card"
        break
      fi
    done
    [ -n "$found" ] || exit 0

    tries=5
    for i in $(seq 1 "$tries"); do
      status="$(wpctl status 2>/dev/null || true)"

      # Find HDSPe hardware sink and game-stereo virtual sink
      hdspe_sink_id="$(echo "$status" | sed -n '/RME AIO Pro.*Pro/{s/^[^0-9]*\([0-9]\+\).*/\1/p;q}')"
      game_sink_id="$(echo "$status" | sed -n '/game-stereo/{s/^[^0-9]*\([0-9]\+\).*/\1/p;q}')"

      # Route game-stereo → HDSPe AUX0/AUX1 and set game-stereo as default
      if [ -n "$hdspe_sink_id" ] && [ -n "$game_sink_id" ]; then
        wpctl set-default "$game_sink_id" || true
        # Connect virtual sink playback to HDSPe AUX0/AUX1
        pw-link playback.game-stereo:output_FL alsa_output.pci-0000_05_00.0.pro-output-0:playback_AUX0 2>/dev/null || true
        pw-link playback.game-stereo:output_FR alsa_output.pci-0000_05_00.0.pro-output-0:playback_AUX1 2>/dev/null || true
        exit 0
      fi
      sleep 1
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
    environment.systemPackages = [
      pwRouteScript
      pkgs.zsh
    ];

    # Symlink routing.yaml for pw-route
    environment.etc."audio/routing.yaml".source = routingYaml;

    # System-level: initialize HDSPe hardware mixer on boot
    systemd.services."hdspe-init-mixer" = {
      description = "Initialize RME HDSPe hardware mixer levels";
      after = [
        "alsa-store.service"
        "sound.target"
      ];
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
      wantedBy = [ "graphical-session.target" ]; # don't block default.target/maid activation
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${hdspeDefaultScript}";
        Environment = "PATH=${
          lib.makeBinPath [
            config.services.pipewire.package
            pkgs.alsa-utils
            pkgs.gnused
            pkgs.coreutils
          ]
        }";
      };
    };

    # User-level: route audio to AES output by default
    systemd.user.services."pw-route-aes" = {
      description = "Route PipeWire audio to RME AES output";
      after = [
        "wp-hdspe-default.service"
        "wireplumber.service"
        "pipewire.service"
      ];
      requires = [ "wp-hdspe-default.service" ];
      partOf = [ "wireplumber.service" ];
      wantedBy = [ "graphical-session.target" ]; # don't block default.target
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.writeShellScript "pw-route-aes" ''
          export PATH="${
            lib.makeBinPath [
              pkgs.zsh
              pkgs.pipewire
              pkgs.gawk
            ]
          }:$PATH"
          tries=5
          for i in $(seq 1 "$tries"); do
            if ${pwRouteScript}/bin/pw-route aes 2>/dev/null; then
              exit 0
            fi
            sleep 1
          done
          exit 0
        ''}";
      };
    };
  };
}
