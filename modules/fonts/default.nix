{
  lib,
  config,
  pkgs,
  iosevkaNeg,
  ...
}:
let
  guiEnabled = config.features.gui.enable or false;

  iosevkaFont = iosevkaNeg.nerd-font or pkgs.nerd-fonts.iosevka;

  packages = [
    pkgs.pango # ensure fontconfig has Pango shaping libs for GTK
    iosevkaFont # patched Iosevka Nerd Font for terminal/UI monospace
  ];
in
{
  config = lib.mkIf guiEnabled {
    fonts.packages = lib.mkAfter packages;
  };
}
