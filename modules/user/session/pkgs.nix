{
  lib,
  pkgs,
  inputs,
  ...
}: let
in {
  # Wayland/Hyprland tools and small utilities
  environment.systemPackages =
    [
      inputs.raise.defaultPackage.${pkgs.stdenv.hostPlatform.system} # run-or-raise for Hyprland
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
      pkgs.wl-clipboard # wl-copy / wl-paste
      pkgs.wl-clip-persist # persist clipboard across app exits
      pkgs.cliphist # persistent Wayland clipboard history
      pkgs.wtype # fake typing for Wayland automation
      pkgs.ydotool # uinput automation helper (autoclicker, etc.)
      pkgs.espanso # text expander daemon
      pkgs.matugen # wallpaper-driven palette/matcap generator
      pkgs.playerctl # MPRIS media controller for bindings
      pkgs.mpc # MPD CLI helper for local scripts
      pkgs.swappy # screenshot editor (optional)
      pkgs.hyprpicker # color picker for Wayland/Hyprland
      pkgs.hyprlandPlugins.hy3
      pkgs.hyprlandPlugins.hyprsplit
    ]
    ++ lib.optionals (pkgs ? uwsm) [pkgs.uwsm];
}
