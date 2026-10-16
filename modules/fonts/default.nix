{
  lib,
  config,
  pkgs,
  iosevkaNeg,
  ...
}:
let
  guiEnabled = config.lib.neg.enabled "gui";

  iosevkaNerd = iosevkaNeg.nerd-font or pkgs.nerd-fonts.iosevka;
  iosevkaNerdQuasi = iosevkaNeg.nerd-font-quasi or iosevkaNerd;
  iosevkaNerdProp = iosevkaNeg.nerd-font-prop or iosevkaNerd;

  # Outfit ships only as a variable TTF in the Google Fonts repo, hence the
  # local package (same pattern as alkano-aio in the gui domain).
  outfit = pkgs.callPackage ./outfit.nix { };

  packages = [
    pkgs.pango # ensure fontconfig has Pango shaping libs for GTK
    iosevkaNerd # patched Iosevka Nerd Font for terminal/UI monospace
    iosevkaNerdQuasi # Iosevka Quasi (QP) for GUI readability
    iosevkaNerdProp # Iosevka Proportional for GUI text
    outfit # Outfit geometric sans variable font (display/UI text)
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
