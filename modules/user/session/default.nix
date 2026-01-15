{ pkgs, ... }:
{
  imports = [
    ./chat.nix
    ./clipboard.nix
    ./greetd.nix
    ./hypr-bindings.nix
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
    # Use pkgs.* here; an overlay routes them to the flake-pinned Hyprland release
    package = pkgs.hyprland; # Dynamic tiling Wayland compositor that doesn't sacrifice ...
    portalPackage = pkgs.xdg-desktop-portal-hyprland; # xdg-desktop-portal backend for Hyprland
  };

  services = {
    accounts-daemon.enable = true; # AccountsService a DBus service for accessing the list of user accounts and info…
    dbus.implementation = "broker";
    gvfs.enable = true;
    libinput.enable = true; # Enable touchpad support (enabled default in most desktopManager).
    ratbagd.enable = true; # gaming mouse setup daemon
  };
}
