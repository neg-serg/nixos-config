{
  pkgs,
  lib,
  config,
  neg,
  impurity ? null,
  ...
}: let
  n = neg impurity;
  cfg = config.features.media.audio.core;
  filesRoot = ../../../files;

  rnnoiseConf = builtins.toJSON {
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

  # Merge static config files with the generated rnnoise config
  pipewireConfD = pkgs.symlinkJoin {
    name = "pipewire.conf.d";
    paths = [
      "${filesRoot}/media/pipewire/pipewire.conf.d"
      (pkgs.writeTextDir "99-rnnoise.conf" rnnoiseConf)
    ];
  };
in {
  config = lib.mkIf (cfg.enable or false) (n.mkHomeFiles {
    ".config/wireplumber" = {
      source = "${filesRoot}/media/wireplumber";
    };
    # Link the merged directory
    ".config/pipewire/pipewire.conf.d".source = pipewireConfD;
  });
}
