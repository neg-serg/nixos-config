{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.hardware.audio.rnnoise or {};
in {
  options.hardware.audio.rnnoise.enable = lib.mkEnableOption "Enable RNNoise-based virtual microphone (PipeWire filter-chain).";

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
      extraConfig.pipewire =
        {
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
                        plugin = "${pkgs.rnnoise-plugin}/lib/ladspa/rnnoise_ladspa.so";
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
        package = pkgs.wireplumber;
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
    systemd.user.services.pipewire.wantedBy = ["default.target"];

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
      in {
        description = "Set RNNoise virtual source as default (wpctl)";
        after = ["wireplumber.service" "pipewire.service"];
        partOf = ["wireplumber.service"];
        wantedBy = ["default.target"];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${script}";
        };
      }
    );
  };
}
