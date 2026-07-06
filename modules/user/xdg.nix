{
  lib,
  pkgs,
  config,
  ...
}:
let
  pnameOf = pkg: (pkg.pname or (builtins.parseDrvName (pkg.name or "")).name);
  excludePkgs = config.features.excludePkgs or [ ];
  filterExcluded = pkgList: lib.filter (pkg: !(builtins.elem (pnameOf pkg) excludePkgs)) pkgList;
  packages = filterExcluded [
    pkgs.handlr # xdg-open replacement with per-handler rules
    pkgs.xdg-utils # classic xdg helpers (xdg-open/xdg-mime/etc.)
    pkgs.xdg-ninja # detect mislocated files in $HOME
  ];
in
{
  environment.systemPackages = lib.mkAfter packages;
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals = [
      # Hyprland portal is provided via programs.hyprland.portalPackage
      pkgs.xdg-desktop-portal-termfilechooser # TUI file picker portal used in rofi/CLI tools
    ];
    config = {
      common.default = [
        "hyprland"
      ];
      common."org.freedesktop.impl.portal.FileChooser" = [ ];
      hyprland.default = [
        "hyprland"
      ];
      hyprland."org.freedesktop.impl.portal.FileChooser" = [ ];
    };
  };

  # Ensure Hyprland portal starts reliably by dropping the ConditionEnvironment
  # check from the user unit. Hyprland already imports the necessary env vars
  # into the systemd user manager at session start.
  systemd.user.services.xdg-desktop-portal-hyprland.unitConfig.ConditionEnvironment = lib.mkForce "";
}
