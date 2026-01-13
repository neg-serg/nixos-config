{
  lib,
  config,
  pkgs,

  ...
}:
let
  guiEnabled = config.features.gui.enable or false;

  iosevkaFont = pkgs.nerd-fonts.iosevka; # fallback
  # if iosevkaInput != null && (iosevkaInput ? nerd-font) then
  #   iosevkaInput.nerd-font
  # else
  #   pkgs.nerd-fonts.iosevka;
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
