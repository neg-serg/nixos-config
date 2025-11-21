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
    pkgs.adw-gtk3 # libadwaita GTK3 port; matches GNOME styling
    pkgs.dconf # dconf CLI to push theme keys system-wide
    iosevkaFont # patched Iosevka Nerd Font for UI monospace
    pkgs.kora-icon-theme # sharp icon pack w/ dark + light variants
    pkgs.flight-gtk-theme # main GTK theme matching Hyprland colors
    pkgs.cantarell-fonts # primary UI sans (GNOME default) for consistency
    pkgs.kdePackages.qtstyleplugin-kvantum # Qt6 Kvantum bridge for GTK-like theming
    pkgs.libsForQt5.qtstyleplugin-kvantum # Qt5 Kvantum plugin for old apps
  ];
in {
  environment.systemPackages = lib.mkAfter packages;
}
