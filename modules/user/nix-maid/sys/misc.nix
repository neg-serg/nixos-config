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
  cfg = config.features;

  # Fun Art Scripts
  artFiles = {
    "bonsai.sh" = ../../../../files/art/fun-art/bonsai.sh;
    "chess.sh" = ../../../../files/art/fun-art/chess.sh;
    "nvim-logo.sh" = ../../../../files/art/fun-art/nvim-logo.sh;
    "rain.sh" = ../../../../files/art/fun-art/rain.sh;
    "skull.sh" = ../../../../files/art/fun-art/skull.sh;
    "skullmono.sh" = ../../../../files/art/fun-art/skullmono.sh;
    "skulls.sh" = ../../../../files/art/fun-art/skulls.sh;
    "skull.txt" = ../../../../files/art/fun-art/skull.txt;
    "zalgo.py" = ../../../../files/art/fun-art/zalgo.py;
    "gandalf.txt" = ../../../../files/art/fun-art/gandalf.txt;
    "helmet.txt" = ../../../../files/art/fun-art/helmet.txt;
    "hydra.txt" = ../../../../files/art/fun-art/hydra.txt;
    "skeleton_hood.txt" = ../../../../files/art/fun-art/skeleton_hood.txt;
  };

  # Rustmission Config Dir
  rustmissionConf = ../../../../files/config/rustmission;
in
{
  config = lib.mkMerge [
    (lib.mkIf (cfg.apps.winapps.enable or false) {
      # Winboat (Bottles/Wine)
      environment.systemPackages = [
        pkgs.bottles # Run Windows software on Linux with Bottles
        pkgs.wineWowPackages.stable # Open-source implementation of the Windows API
      ];
    })
    (lib.mkIf (cfg.fun.enable or false) (
      n.mkHomeFiles (
        lib.mkMerge [
          # Hack Art
          (lib.mapAttrs' (
            name: src:
            lib.nameValuePair ".local/share/hack-art/${name}" {
              source = src;
              executable = lib.hasSuffix ".sh" name || lib.hasSuffix ".py" name;
            }
          ) artFiles)

          # Fantasy Art
          {
            ".local/share/fantasy-art/gandalf.txt".source = ../../../../files/art/fun-art/gandalf.txt;
            ".local/share/fantasy-art/helmet.txt".source = ../../../../files/art/fun-art/helmet.txt;
            ".local/share/fantasy-art/hydra.txt".source = ../../../../files/art/fun-art/hydra.txt;
            ".local/share/fantasy-art/skeleton_hood.txt".source =
              ../../../../files/art/fun-art/skeleton_hood.txt;
          }

          # Rustmission
          {
            ".config/rustmission/config.toml".source = "${rustmissionConf}/config.toml";
            ".config/rustmission/keymap.toml".source = "${rustmissionConf}/keymap.toml";
            ".config/rustmission/categories.toml".source = "${rustmissionConf}/categories.toml";
          }
        ]
      )
    ))
  ];
}
