{
  lib,
  pkgs,
  config,
  iosevkaNeg,
  ...
}:
let
  iosevkaFont = iosevkaNeg.nerd-font or pkgs.nerd-fonts.iosevka; # fallback iosevka font
  packages = [
    iosevkaFont # patched Iosevka Nerd Font for UI monospace
    pkgs.kdePackages.qtstyleplugin-kvantum # Qt6 Kvantum bridge for theme consistency
    pkgs.kora-icon-theme # sharp icon pack w/ dark + light variants
  ];
in
{
  environment.systemPackages = lib.mkAfter packages;
}
