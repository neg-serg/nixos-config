{
  lib,
  pkgs,
  config,
  ...
}: let
  pnameOf = pkg: (pkg.pname or (builtins.parseDrvName (pkg.name or "")).name);
  excludePkgs = config.features.excludePkgs or [];
  filterExcluded = pkgList: lib.filter (pkg: !(builtins.elem (pnameOf pkg) excludePkgs)) pkgList;
  packages = filterExcluded [
    pkgs.handlr # xdg-open replacement with per-handler rules
    pkgs.xdg-utils # classic xdg helpers (xdg-open/xdg-mime/etc.)
    pkgs.xdg-ninja # detect mislocated files in $HOME
  ];
in {
  environment.systemPackages = lib.mkAfter packages;
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals = [
      # Hyprland portal is provided via programs.hyprland.portalPackage
      pkgs.xdg-desktop-portal-termfilechooser
      pkgs.xdg-desktop-portal-gtk
    ];
    config = {
      common.default = ["hyprland" "gtk"];
      common."org.freedesktop.impl.portal.FileChooser" = ["gtk"];
      hyprland.default = ["hyprland" "gtk"];
      hyprland."org.freedesktop.impl.portal.FileChooser" = ["gtk"];
      # Plasma-specific portal defaults removed to restore Hyprland-only setup
    };
  };
}
