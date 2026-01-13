{
  lib,
  pkgs,
  inputs,
  iosevkaNeg,
  ...
}:
let
  iosevkaFont =
    if iosevkaNeg ? nerd-font then
      iosevkaNeg.nerd-font
    else
      pkgs.nerd-fonts.iosevka; # fallback iosevka font
  packages = [
    iosevkaFont # patched Iosevka Nerd Font for UI monospace
    pkgs.adw-gtk3 # libadwaita GTK3 port; matches GNOME styling
    pkgs.cantarell-fonts # primary UI sans (GNOME default) for consistency
    pkgs.dconf # dconf CLI to push theme keys system-wide
    pkgs.flight-gtk-theme # main GTK theme matching Hyprland colors
    pkgs.kdePackages.qtstyleplugin-kvantum # Qt6 Kvantum bridge for GTK-like theming
    pkgs.kora-icon-theme # sharp icon pack w/ dark + light variants
    pkgs.libsForQt5.qtstyleplugin-kvantum # Qt5 Kvantum plugin for old apps
  ];
in
{
  environment.systemPackages = lib.mkAfter packages;
}
