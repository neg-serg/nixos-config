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
      pkgs.grimblast # Hyprland-friendly screenshots (grim+slurp+wl-copy)
      pkgs.grim # raw screenshot helper for clip wrappers
      pkgs.slurp # select regions for grim/wlroots compositors
      pkgs.wl-clipboard # wl-copy / wl-paste
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
    ];
}
