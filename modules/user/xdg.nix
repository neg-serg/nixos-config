{pkgs, ...}: {
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
