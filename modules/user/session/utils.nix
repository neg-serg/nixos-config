{
  config,
  lib,
  pkgs,
  ...
}:
let
  devSpeed = config.features.devSpeed.enable or false;
  guiEnabled = config.features.gui.enable or false;
  wifiEnabled = config.features.services.wifi.enable or false;
  menuPkgs = if guiEnabled && !devSpeed && wifiEnabled then [ pkgs.iwmenu ] else [ ]; # Launcher-driven Wi-Fi manager for Linux
in
{
  environment.systemPackages = [
    # -- Dialogs / Automation --
    pkgs.wtype # fake typing for Wayland automation
    pkgs.ydotool # uinput automation helper (autoclicker, etc.)

    # -- Notifications --
    pkgs.dunst # notification daemon + dunstctl

    # -- Power --
    pkgs.upower # power management daemon for laptops/desktops

    # -- SVG / Graphics --
    pkgs.libxml2 # xmllint for SVG validation

    # -- Viewer --
    (pkgs.zathura.override { plugins = [ pkgs.zathuraPkgs.zathura_pdf_mupdf ]; }) # lightweight document viewer (PDF only)

    # -- Wayland Utils --
    pkgs.networkmanager # CLI nmcli helper for panels
    pkgs.waypipe # Wayland remoting (ssh -X like)
    pkgs.wev # xev for Wayland
  ]
  ++ lib.optional (config.features.text.espanso.enable or false) pkgs.espanso
  ++ menuPkgs;
}
