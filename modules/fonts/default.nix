{
  lib,
  config,
  pkgs,
  inputs ? {},
  ...
}: let
  guiEnabled = config.features.gui.enable or false;
  system = pkgs.stdenv.hostPlatform.system;
  iosevkaInput =
    if inputs ? "iosevka-neg"
    then inputs."iosevka-neg".packages.${system}
    else null;
  iosevkaFont =
    if iosevkaInput != null && (iosevkaInput ? nerd-font)
    then iosevkaInput.nerd-font
    else pkgs.nerd-fonts.iosevka;
  packages = [
    pkgs.pango
    iosevkaFont
  ];
in {
  config = lib.mkIf guiEnabled {
    fonts.packages = lib.mkAfter packages;
  };
}
