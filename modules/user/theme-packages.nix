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
    pkgs.kdePackages.qtstyleplugin-kvantum # Qt6 Kvantum bridge for theme consistency
    # The package itself is patched in packages/overlays/gui.nix: nixpkgs
    # propagates its fallback themes as dev outputs, which leaked the Qt/GTK dev
    # trees (breeze-icons-dev -> qtsvg-dev -> qtbase-dev -> vulkan-headers, …)
    # into the system closure.
    pkgs.kora-icon-theme # sharp icon pack w/ dark + light variants
  ];
in
{
  environment.systemPackages = lib.mkAfter packages;
}
