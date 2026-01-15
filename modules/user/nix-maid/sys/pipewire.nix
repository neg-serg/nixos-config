{
  pkgs,
  lib,
  config,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  cfg = config.features.media.audio.core;
  filesRoot = ../../../../files;

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
                "plugin" = "${pkgs.rnnoise-plugin}/lib/ladspa/librnnoise_ladspa.so"; # Real-time noise suppression plugin for voice based on Xip...
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

  cfgAudio = config.features.media.audio;

  # Build the pipewire.conf.d directory dynamically
  pipewireConfD = pkgs.runCommand "pipewire.conf.d" { } ''
    mkdir -p $out
    # Copy all static configs from files/
    cp ${filesRoot}/media/pipewire/pipewire.conf.d/*.conf $out/
    # Remove the loopback sink if not enabled
    ${lib.optionalString (!cfgAudio.carlaLoopback.enable) "rm -f $out/10-virtual-sink.conf"}
    # Add the generated rnnoise config
    ln -s ${pkgs.writeText "99-rnnoise.conf" rnnoiseConf} $out/99-rnnoise.conf
  '';
in
{
  config = lib.mkIf (cfg.enable or false) (
    lib.mkMerge [
      (n.mkHomeFiles {
        ".config/wireplumber" = {
          source = "${filesRoot}/media/wireplumber";
        };
        # Link the merged directory
        ".config/pipewire/pipewire.conf.d".source = pipewireConfD;
      })
      {
        environment.variables = {
          PIPEWIRE_DEBUG = "0";
          PIPEWIRE_LOG_SYSTEMD = "true";
        };
      }
    ]
  );
}
