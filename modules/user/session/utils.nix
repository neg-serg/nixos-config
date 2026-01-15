{
  config,

  pkgs,
  ...
}:
let
  devSpeed = config.features.devSpeed.enable or false;
  guiEnabled = config.features.gui.enable or false;
  menuPkgs = if guiEnabled && !devSpeed then [ pkgs.iwmenu ] else [ ]; # Launcher-driven Wi-Fi manager for Linux
in
{
  environment.systemPackages = [
    # -- Dialogs / Automation --
    pkgs.espanso # text expander daemon
    pkgs.wtype # fake typing for Wayland automation
    pkgs.ydotool # uinput automation helper (autoclicker, etc.)

    # -- Notifications --
    pkgs.dunst # notification daemon + dunstctl

    # -- Power --
    pkgs.upower # power management daemon for laptops/desktops

    # -- SVG / Graphics --
    pkgs.librsvg # rsvg-convert for assets
    pkgs.libxml2 # xmllint for SVG validation

    # -- Viewer --
    pkgs.zathura # lightweight document viewer for rofi wrappers

    # -- Wayland Utils --
    pkgs.networkmanager # CLI nmcli helper for panels
    pkgs.waypipe # Wayland remoting (ssh -X like)
    pkgs.wev # xev for Wayland
  ]
  ++ menuPkgs;
}
