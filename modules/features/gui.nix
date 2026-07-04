{ lib, ... }:
with lib;
let
  mkBool = desc: default: (lib.mkEnableOption desc) // { inherit default; };
in
{
  options.features.gui = {
    enable = mkBool "enable GUI stack (wayland/hyprland, quickshell, etc.)" true;
    qt.enable = mkBool "enable Qt integrations for GUI (qt6ct, hyprland-qt-*)" true;
    quickshell = {
      enable = mkBool "enable Quickshell (panel) at login" true;
      flavor = lib.mkOption {
        type = types.enum [ "default" "octashell" ];
        default = "default";
        description = "Which quickshell configuration flavor to use (default or octashell).";
      };
    };
    gtkTheme = lib.mkOption {
      type = types.enum [ "Flight-Dark-GTK" "Andromeda" ];
      default = "Flight-Dark-GTK";
      description = "GTK theme to apply system-wide.";
    };
  };
}
