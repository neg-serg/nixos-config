{pkgs, ...}: {
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals = [
      # Hyprland portal is provided via programs.hyprland.portalPackage
      pkgs.xdg-desktop-portal-termfilechooser
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-kde
    ];
    config = {
      common.default = ["hyprland" "gtk"];
      common."org.freedesktop.impl.portal.FileChooser" = ["gtk"];
      hyprland.default = ["hyprland" "gtk"];
      hyprland."org.freedesktop.impl.portal.FileChooser" = ["gtk"];
      # Use KDE portal implementations when running Plasma
      plasma.default = ["kde" "gtk"];
    };
  };
}
