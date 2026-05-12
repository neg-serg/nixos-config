{ lib, ... }:
with lib;
let
  mkBool = desc: default: (lib.mkEnableOption desc) // { inherit default; };
in
{
  options.features.gui = {
    enable = mkBool "enable GUI stack (wayland/hyprland, quickshell, etc.)" true;
    hy3.enable = mkBool "enable the hy3 tiling plugin for Hyprland" true;
    qt.enable = mkBool "enable Qt integrations for GUI (qt6ct, hyprland-qt-*)" true;
    quickshell.enable = mkBool "enable Quickshell (panel) at login" true;
    walker.enable = mkBool "enable Walker application launcher" true;
  };
}
