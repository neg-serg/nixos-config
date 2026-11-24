{
  neg,
  pkgs,
  ...
}:
{
  imports = neg.importDir { dir = ./.; };

  programs.hyprland = {
    enable = true;
    package = pkgs.hyprland;
    portalPackage = pkgs.xdg-desktop-portal-hyprland;
  };

  services = {
    dbus.implementation = "broker";
    libinput.enable = true;
    ratbagd.enable = true;
  };
}
