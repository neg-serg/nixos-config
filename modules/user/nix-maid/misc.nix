{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.features;

  # Fun Art Scripts
  artFiles = {
    "bonsai.sh" = ../../../home/modules/misc/fun-art/bonsai.sh;
    "chess.sh" = ../../../home/modules/misc/fun-art/chess.sh;
    "nvim-logo.sh" = ../../../home/modules/misc/fun-art/nvim-logo.sh;
    "rain.sh" = ../../../home/modules/misc/fun-art/rain.sh;
    "skull.sh" = ../../../home/modules/misc/fun-art/skull.sh;
    "skullmono.sh" = ../../../home/modules/misc/fun-art/skullmono.sh;
    "skulls.sh" = ../../../home/modules/misc/fun-art/skulls.sh;
    "skull.txt" = ../../../home/modules/misc/fun-art/skull.txt;
    "zalgo.py" = ../../../home/modules/misc/fun-art/zalgo.py;
    "gandalf.txt" = ../../../home/modules/misc/fun-art/gandalf.txt;
    "helmet.txt" = ../../../home/modules/misc/fun-art/helmet.txt;
    "hydra.txt" = ../../../home/modules/misc/fun-art/hydra.txt;
    "skeleton_hood.txt" = ../../../home/modules/misc/fun-art/skeleton_hood.txt;
  };

  # Rustmission Config Dir
  rustmissionConf = ../../../home/modules/misc/rustmission/conf;
in {
  # Fun Art Installation & Rustmission
  users.users.neg.maid.file.home = lib.mkIf (cfg.fun.enable or false) (lib.mkMerge [
    # Hack Art
    (lib.mapAttrs' (name: src:
      lib.nameValuePair ".local/share/hack-art/${name}" {
        source = src;
        executable = lib.hasSuffix ".sh" name || lib.hasSuffix ".py" name;
      })
    artFiles)

    # Fantasy Art
    {
      ".local/share/fantasy-art/gandalf.txt".source = ../../../home/modules/misc/fun-art/gandalf.txt;
      ".local/share/fantasy-art/helmet.txt".source = ../../../home/modules/misc/fun-art/helmet.txt;
      ".local/share/fantasy-art/hydra.txt".source = ../../../home/modules/misc/fun-art/hydra.txt;
      ".local/share/fantasy-art/skeleton_hood.txt".source = ../../../home/modules/misc/fun-art/skeleton_hood.txt;
    }

    # Rustmission
    {
      ".config/rustmission".source = rustmissionConf;
    }
  ]);

  # Winboat (Bottles/Wine)
  environment.systemPackages = with pkgs; [
    bottles
    wineWowPackages.stable
  ];
}
