{
  lib,
  pkgs,
  inputs,
  ...
}: let
  mkQuickshellWrapper = import ../../../lib/quickshell-wrapper.nix {
    inherit lib pkgs;
  };
  quickshellPkg = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;
  quickshellWrapped = mkQuickshellWrapper {qsPkg = quickshellPkg;};
in {
  # Wayland/Hyprland tools and small utilities
  environment.systemPackages =
    [
      inputs.raise.defaultPackage.${pkgs.stdenv.hostPlatform.system} # run-or-raise for Hyprland
      quickshellWrapped # wrapped quickshell binary with required envs
      pkgs.xorg.xeyes # track eyes for your cursor
      pkgs.swaybg # simple wallpaper setter
      pkgs.dragon-drop # drag-n-drop from console
      pkgs.gowall # generate palette from wallpaper
      pkgs.grimblast # Hyprland-friendly screenshots (grim+slurp+wl-copy)
      pkgs.grim # raw screenshot helper for clip wrappers
      pkgs.slurp # select regions for grim/wlroots compositors
      pkgs.swww # Wayland wallpaper daemon
      pkgs.waybar # Wayland status bar
      pkgs.waypipe # Wayland remoting (ssh -X like)
      pkgs.wev # xev for Wayland
      pkgs.wf-recorder # screen recording
      pkgs.zathura # lightweight document viewer for rofi wrappers
      pkgs.dunst # notification daemon + dunstctl
      pkgs.wl-clipboard # wl-copy / wl-paste
      pkgs.wl-clip-persist # persist clipboard across app exits
      pkgs.cliphist # persistent Wayland clipboard history
      pkgs.wtype # fake typing for Wayland automation
      pkgs.ydotool # uinput automation helper (autoclicker, etc.)
      pkgs.espanso # text expander daemon
      pkgs.matugen # wallpaper-driven palette/matcap generator
      pkgs.playerctl # MPRIS media controller for bindings
      pkgs.mpc # MPD CLI helper for local scripts
      pkgs.hyprcursor # modern cursor theme format for Hyprland
      pkgs.hypridle # idle daemon for Hyprland sessions
      pkgs.swappy # screenshot editor (optional)
      pkgs.hyprpicker # color picker for Wayland/Hyprland
      pkgs.hyprpolkitagent # Wayland-friendly polkit agent
      pkgs.hyprprop # Hyprland property helper (xprop-like)
      pkgs.hyprutils # assorted Hyprland utilities
      pkgs.pyprland # Hyprland plugin/runtime helper
      pkgs.upower # power management daemon for laptops/desktops
      pkgs.hyprland-qt-support # Qt integration helpers for Hyprland
      pkgs.hyprland-qtutils # Qt extras (hyprland-qt-helper)
      pkgs.kdePackages.qt6ct # Qt6 configuration utility
      pkgs.cantarell-fonts # UI font for panels/widgets
      pkgs.cava # console audio visualizer for quickshell HUD
      pkgs.kdePackages.kdialog # Qt dialog helper
      pkgs.kdePackages.qt5compat # Qt6 QtQuick bridge
      pkgs.kdePackages.qtdeclarative # QtDeclarative (QML runtime)
      pkgs.kdePackages.qtimageformats # extra Qt image formats
      pkgs.kdePackages.qtmultimedia # Qt multimedia modules
      pkgs.kdePackages.qtpositioning # Qt positioning (sensors)
      pkgs.kdePackages.qtquicktimeline # Qt timeline module
      pkgs.kdePackages.qtsensors # Qt sensors module
      pkgs.kdePackages.qtsvg # Qt SVG backend
      pkgs.kdePackages.qttools # Qt utility tooling
      pkgs.kdePackages.qttranslations # Qt translations set
      pkgs.kdePackages.qtvirtualkeyboard # Qt virtual keyboard
      pkgs.kdePackages.qtwayland # Qt Wayland plugin
      pkgs.kdePackages.syntax-highlighting # KSyntaxHighlighting for QML
      pkgs.libxml2 # xmllint for SVG validation
      pkgs.librsvg # rsvg-convert for assets
      pkgs.networkmanager # CLI nmcli helper for panels
      pkgs.qt6.qtimageformats # supplemental Qt6 image formats
      pkgs.qt6.qtsvg # supplemental Qt6 SVG support
      pkgs.kitty # primary GUI terminal emulator
      pkgs.kitty-img # inline image helper for Kitty
      pkgs.telegram-desktop # Telegram GUI client
      pkgs.tdl # Telegram CLI uploader/downloader
      pkgs.vesktop # Discord (Vencord) desktop client
      pkgs.nchat # terminal-first Telegram client
      pkgs.hyprlandPlugins.hy3
      pkgs.hyprlandPlugins.hyprsplit
    ]
    ++ lib.optionals (pkgs ? uwsm) [pkgs.uwsm];
}
