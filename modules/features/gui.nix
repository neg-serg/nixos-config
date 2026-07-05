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
        type = types.enum [ "default" "octashell" "sshell" ];
        default = "default";
        description = "Which quickshell configuration flavor to use (default, octashell, or sshell).";
      };
    };
    caelestia-shell.enable = mkBool "enable Caelestia Desktop Shell (built on Quickshell)" false;
    skwd.enable = mkBool "enable Skwd desktop shell (bar, launcher, music, notifications, settings, switcher) and skwd-daemon" false;
    exo.enable = mkBool "Exo desktop shell (Material 3 deskbar for Ignis/Hyprland/Niri)" false;
    noctalia.enable = mkBool "enable Noctalia Wayland shell (bar/panel)" false;
    gtkTheme = lib.mkOption {
      type = types.enum [ "Flight-Dark-GTK" "Andromeda" ];
      default = "Flight-Dark-GTK";
      description = "GTK theme to apply system-wide.";
    };
  };
}
