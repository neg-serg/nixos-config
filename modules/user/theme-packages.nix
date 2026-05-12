{
  lib,
  pkgs,

  iosevkaNeg,
  ...
}:
let
  iosevkaFont = iosevkaNeg.nerd-font or pkgs.nerd-fonts.iosevka; # fallback iosevka font
  packages = [
    iosevkaFont # patched Iosevka Nerd Font for UI monospace
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
