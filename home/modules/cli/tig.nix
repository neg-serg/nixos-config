{
  lib,
  config,
  pkgs,
  xdg,
  ...
}:
lib.mkMerge [
  {
    # Install tig and provide its configuration via XDG
    home.packages = config.lib.neg.pkgsList [
      pkgs.tig # text-mode interface for Git
    ];
  }
  (xdg.mkXdgText "tig/config" (builtins.readFile ./tig.conf))
]
