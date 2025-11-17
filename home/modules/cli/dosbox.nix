{
  pkgs,
  lib,
  config,
  xdg,
  ...
}:
lib.mkMerge [
  {
    # Install dosbox-staging and ship config via XDG
    home.packages = config.lib.neg.pkgsList [
      pkgs.dosbox-staging # DOS/retro games emulator (staging fork)
    ];
  }
  (xdg.mkXdgSource "dosbox" {source = ./dosbox-conf;})
]
