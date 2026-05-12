{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.hardware.audio.rnnoise or { };
  rmeSinkName = "alsa_output.usb-RME_ADI-2_4_Pro_SE__53011083__B992903C2BD8DC8-00.iec958-stereo";
  rmeSourceName = "alsa_input.usb-RME_ADI-2_4_Pro_SE__53011083__B992903C2BD8DC8-00.analog-stereo";
  rmeDefaultScript = pkgs.writeShellScript "wpctl-set-rme-default" ''
    set -euo pipefail
    jq_bin=${pkgs.jq}/bin/jq # Lightweight and flexible command-line JSON processor
    pw_dump_bin=${pkgs.pipewire}/bin/pw-dump # Server and user space API to deal with multimedia pipelines
    wpctl_bin=${pkgs.pipewire}/bin/wpctl # Server and user space API to deal with multimedia pipelines
    tries=60
    for i in $(seq 1 "$tries"); do
      dump="$("$pw_dump_bin" || true)"
      if [ -z "$dump" ]; then
        sleep 0.5
        continue
      fi
      sink_id="$("$jq_bin" -r --arg name "${rmeSinkName}" '
        .[] | select(.type=="PipeWire:Interface:Node" and .info.props["node.name"]==$name) | .id
      ' <<<"$dump" | head -n1 | tr -d '\n')"
      source_id="$("$jq_bin" -r --arg name "${rmeSourceName}" '
        .[] | select(.type=="PipeWire:Interface:Node" and .info.props["node.name"]==$name) | .id
      ' <<<"$dump" | head -n1 | tr -d '\n')"
      done=0
      if [ -n "$sink_id" ]; then
        "$wpctl_bin" set-default "$sink_id" || true
        done=$((done + 1))
      fi
      if [ -n "$source_id" ]; then
        "$wpctl_bin" set-default "$source_id" || true
        done=$((done + 1))
      fi
      if [ "$done" -gt 0 ]; then
        exit 0
      fi
      sleep 0.5
    done
    exit 0
  '';
in
{
  options.hardware.audio.rnnoise.enable =
    lib.mkEnableOption "Enable RNNoise-based virtual microphone (PipeWire filter-chain).";

  config = {
    # Default to enabled globally; hosts can override to false
    hardware.audio.rnnoise.enable = lib.mkDefault true;

    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
      # Base low-latency tuning + optional RNNoise virtual mic
      extraConfig.pipewire = {
        "92-low-latency" = {
          "context.properties" = {
            "default.clock.rate" = 48000;
            "default.clock.quantum" = 128;
            "default.clock.min-quantum" = 32;
            "default.clock.max-quantum" = 2048;
          };
        };
      }
      // lib.optionalAttrs (cfg.enable or false) {
        "95-rnnoise-filter-chain" = {
          "context.modules" = [
            {
              name = "libpipewire-module-filter-chain";
              args = {
                "node.name" = "rnnoise_source";
                "node.description" = "Noise Canceling (RNNoise)";
                "media.class" = "Audio/Source";
                "filter.graph" = {
                  nodes = [
                    {
                      type = "ladspa";
                      name = "rnnoise";
                      plugin = "${pkgs.rnnoise-plugin}/lib/ladspa/rnnoise_ladspa.so"; # Real-time noise suppression plugin for voice based on Xip...
                      label = "noise_suppressor_stereo";
                    }
                  ];
                };
                "capture.props" = {
                  "node.passive" = true;
                  "node.description" = "RNNoise Input";
                };
                "playback.props" = {
                  "node.description" = "RNNoise Source";
                };
              };
            }
          ];
        };
      };
      wireplumber = {
        package = pkgs.wireplumber; # Modular session / policy manager for PipeWire
        extraConfig = {
          # # Tell wireplumber to be more verbose
          # "10-log-level-debug" = {
          #   "context.properties"."log.level" = "D"; # output debug logs
          # };
          # Default volume is by default set to 0.4 instead set it to 1.0
          "10-default-volume" = {
            "wireplumber.settings"."device.routes.default-sink-volume" = 1.0;
          };
        };
      };
    };
    # run pipewire on default.target, this fixes xdg-portal startup delay
    systemd.user.services.pipewire.wantedBy = [ "default.target" ];

    # Try to make RNNoise the default source automatically once WirePlumber is up
    systemd.user.services."wp-rnnoise-default" = lib.mkIf (cfg.enable or false) (
      let
        script = pkgs.writeShellScript "wpctl-set-rnnoise-default" ''
          set -euo pipefail
          for i in $(seq 1 60); do
            if wpctl status | grep -q "rnnoise_source"; then
              wpctl set-default rnnoise_source || true
              exit 0
            fi
            sleep 0.25
          done
          exit 0
        '';
      in
      {
        description = "Set RNNoise virtual source as default (wpctl)";
        after = [
          "wireplumber.service"
          "pipewire.service"
        ];
        partOf = [ "wireplumber.service" ];
        wantedBy = [ "default.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${script}";
        };
      }
    );
    systemd.user.services."wp-rme-default" = {
      description = "Ensure RME ADI-2/4 analog nodes are default (wpctl)";
      after = [
        "wireplumber.service"
        "pipewire.service"
      ];
      partOf = [ "wireplumber.service" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${rmeDefaultScript}";
      };
    };
  };
}
