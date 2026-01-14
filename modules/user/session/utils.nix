{
  config,

  pkgs,
  ...
}:
let
  devSpeed = config.features.devSpeed.enable or false;
  guiEnabled = config.features.gui.enable or false;
  menuPkgs = if guiEnabled && !devSpeed then [ pkgs.iwmenu ] else [ ];
in
{
  environment.systemPackages = [
    # -- Dialogs / Automation --
    pkgs.espanso # text expander daemon
    pkgs.kdePackages.kdialog # Qt dialog helper
    pkgs.wtype # fake typing for Wayland automation
    pkgs.ydotool # uinput automation helper (autoclicker, etc.)

    # -- Fonts --
    pkgs.cantarell-fonts # UI font for panels/widgets

    # -- Notifications --
    pkgs.dunst # notification daemon + dunstctl

    # -- Power --
    pkgs.upower # power management daemon for laptops/desktops

    # -- Sharing --
    pkgs.localsend # AirDrop-like local file sharing

    # -- SVG / Graphics --
    pkgs.librsvg # rsvg-convert for assets
    pkgs.libxml2 # xmllint for SVG validation

    # -- Viewer --
    pkgs.zathura # lightweight document viewer for rofi wrappers

    # -- Wayland Utils --
    pkgs.dragon-drop # drag-n-drop from console
    pkgs.networkmanager # CLI nmcli helper for panels
    pkgs.waypipe # Wayland remoting (ssh -X like)
    pkgs.wev # xev for Wayland
    pkgs.xorg.xeyes # track eyes for your cursor
  ]
  ++ menuPkgs;
}
