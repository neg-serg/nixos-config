{ lib, pkgs, iosevkaNeg, ... }:
let
  iosevkaFont = iosevkaNeg.nerd-font or pkgs.nerd-fonts.iosevka; # fallback iosevka font
  packages = [
    iosevkaFont # patched Iosevka Nerd Font for UI monospace
    pkgs.kdePackages.qtstyleplugin-kvantum # Qt6 Kvantum bridge for theme consistency
    pkgs.kora-icon-theme # sharp icon pack w/ dark + light variants
    # Catppuccin Kvantum — Mocha variant themes for interactive browsing
    (pkgs.catppuccin-kvantum.override {
      variant = "mocha";
      accent = "blue";
    })
    (pkgs.catppuccin-kvantum.override {
      variant = "mocha";
      accent = "mauve";
    })
    (pkgs.catppuccin-kvantum.override {
      variant = "mocha";
      accent = "lavender";
    })
    (pkgs.catppuccin-kvantum.override {
      variant = "mocha";
      accent = "sky";
    })
    (pkgs.catppuccin-kvantum.override {
      variant = "mocha";
      accent = "green";
    })
  ];
in
{
  environment.systemPackages = lib.mkAfter packages;
}
