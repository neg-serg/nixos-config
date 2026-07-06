{
  lib,
  pkgs,
  config,
  iosevkaNeg,
  ...
}:
let
  iosevkaFont = iosevkaNeg.nerd-font or pkgs.nerd-fonts.iosevka; # fallback iosevka font
  gtkTheme = config.features.gui.gtkTheme or "Flight-Dark-GTK";
  gtkThemePkg = {
    "Flight-Dark-GTK" = pkgs.flight-gtk-theme;
    "Andromeda" = pkgs.andromeda-gtk-theme;
  }.${gtkTheme} or pkgs.flight-gtk-theme;
  packages = [
    iosevkaFont # patched Iosevka Nerd Font for UI monospace
    pkgs.dconf # dconf CLI to push theme keys system-wide
    gtkThemePkg # GTK theme (selected via features.gui.gtkTheme)
    pkgs.kdePackages.qtstyleplugin-kvantum # Qt6 Kvantum bridge for GTK-like theming
    pkgs.kora-icon-theme # sharp icon pack w/ dark + light variants
    pkgs.adwaita-icon-theme # base fallback icons for apps Kora doesn't cover
    pkgs.libsForQt5.qtstyleplugin-kvantum # Qt5 Kvantum plugin for old apps
  ];
in
{
  environment.systemPackages = lib.mkAfter packages;
}
