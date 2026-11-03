{
  config,
  pkgs,
  ...
}:
let
  devSpeed = config.lib.neg.enabled "devSpeed";
  guiEnabled = config.lib.neg.enabled "gui";
  wifiEnabled = config.lib.neg.enabled "net.wifi";
  menuPkgs = if guiEnabled && !devSpeed && wifiEnabled then [ pkgs.iwmenu ] else [ ]; # Launcher-driven Wi-Fi manager for Linux
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") { inherit pkgs; };
in
{
  environment.systemPackages = [
    # -- Dialogs / Automation --
    pkgs.wtype # fake typing for Wayland automation
    pkgs.ydotool # uinput automation helper (autoclicker, etc.)

    # -- Power --
    pkgs.upower # power management daemon for laptops/desktops

    # -- SVG / Graphics --
    pkgs.libxml2 # xmllint for SVG validation

    # -- Viewer --
    (onDemand {
      name = "sioyek";
      attr = "sioyek";
    }) # PDF viewer for research papers, built on demand
    (pkgs.makeDesktopItem {
      name = "sioyek";
      desktopName = "Sioyek";
      exec = "sioyek %f";
      icon = "sioyek-icon-linux";
      categories = [
        "Office"
        "Viewer"
      ];
      mimeTypes = [ "application/pdf" ];
    })

    # -- Wayland Utils --
    pkgs.networkmanager # CLI nmcli helper for panels
    pkgs.waypipe # Wayland remoting (ssh -X like)
    pkgs.wev # xev for Wayland
  ]
  ++ menuPkgs;
}
