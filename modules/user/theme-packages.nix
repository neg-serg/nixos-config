{
  lib,
  pkgs,
  inputs,
  ...
}: let
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
    pkgs.adw-gtk3
    pkgs.dconf
    iosevkaFont
    pkgs.kora-icon-theme
    pkgs.flight-gtk-theme
    pkgs.cantarell-fonts
    pkgs.kdePackages.qtstyleplugin-kvantum
    pkgs.libsForQt5.qtstyleplugin-kvantum
  ];
in {
  environment.systemPackages = lib.mkAfter packages;
}
