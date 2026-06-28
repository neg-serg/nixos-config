{ pkgs, ... }:
{
  imports = [
    ./chat.nix
    ./clipboard.nix
    ./greetd.nix
    ./hyprland.nix
    ./media.nix
    ./qt.nix
    ./quickshell.nix
    ./screenshot.nix
    ./terminal.nix
    ./theme.nix
    ./utils.nix
  ];

  programs.hyprland = {
    enable = true;
    package = pkgs.hyprland;
    portalPackage = pkgs.xdg-desktop-portal-hyprland;
  };

  services = {
    accounts-daemon.enable = true;
    dbus.implementation = "broker";
    gvfs.enable = true;
    libinput.enable = true;
    ratbagd.enable = true;
  };
}
