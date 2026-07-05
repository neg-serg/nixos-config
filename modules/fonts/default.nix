{
  lib,
  config,
  pkgs,
  iosevkaNeg,
  ...
}:
let
  guiEnabled = config.features.gui.enable or false;

  iosevkaNerd = iosevkaNeg.nerd-font or pkgs.nerd-fonts.iosevka;
  iosevkaNerdQuasi = iosevkaNeg.nerd-font-quasi or iosevkaNerd;
  iosevkaNerdProp = iosevkaNeg.nerd-font-prop or iosevkaNerd;

  packages = [
    pkgs.pango # ensure fontconfig has Pango shaping libs for GTK
    iosevkaNerd # patched Iosevka Nerd Font for terminal/UI monospace
    iosevkaNerdQuasi # Iosevka Quasi (QP) for GUI readability
    iosevkaNerdProp # Iosevka Proportional for GUI text
  ];
in
{
  config = lib.mkIf guiEnabled {
    fonts.packages = lib.mkAfter packages;
    fonts.fontconfig.defaultFonts = {
      serif = [ "Iosevka" ];
      sansSerif = [ "Iosevka" ];
      monospace = [ "Iosevka" ];
    };
  };
}
