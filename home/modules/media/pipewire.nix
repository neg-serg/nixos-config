{
  lib,
  config,
  pkgs,
  ...
}: let
  filesRoot = "${config.neg.hmConfigRoot}/files";
in
  lib.mkIf (config.features.media.audio.core.enable or false) {
    xdg.configFile = {
      "wireplumber" = {
        source = filesRoot + "/media/wireplumber";
        recursive = true;
      };
      "pipewire" = {
        source = filesRoot + "/media/pipewire";
        recursive = true;
      };
      "pipewire/pipewire.conf.d/99-rnnoise.conf".text = builtins.toJSON {
        "context.modules" = [
          {
            "name" = "libpipewire-module-filter-chain";
            "args" = {
              "node.description" = "Noise Canceling source";
              "media.name" = "Noise Canceling source";
              "filter.graph" = {
                "nodes" = [
                  {
                    "type" = "ladspa";
                    "name" = "rnnoise";
                    "plugin" = "${pkgs.rnnoise-plugin}/lib/ladspa/librnnoise_ladspa.so";
                    "label" = "noise_suppressor_stereo";
                    "control" = {
                      "VAD Threshold (%)" = 50.0;
                    };
                  }
                ];
              };
              "audio.position" = [
                "FL"
                "FR"
              ];
              "capture.props" = {
                "node.name" = "effect_input.rnnoise";
                "node.passive" = true;
              };
              "playback.props" = {
                "node.name" = "effect_output.rnnoise";
                "media.class" = "Audio/Source";
              };
            };
          }
        ];
      };
    };
  }
