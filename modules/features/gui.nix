{ lib, mkBool, ... }:
with lib;
{
  options.features.gui = {
    enable = mkBool "enable GUI stack (wayland/hyprland, quickshell, etc.)" true;
    qt.enable = mkBool "enable Qt integrations for GUI (qt6ct, hyprland-qt-*)" true;
    quickshell = {
      enable = mkBool "enable Quickshell (panel) at login" true;
      flavor = lib.mkOption {
        type = types.enum [
          "default"
        ];
        default = "default";
        description = "Which quickshell configuration flavor to use.";
      };
    };
    caelestia-shell.enable = mkBool "enable Caelestia Desktop Shell (built on Quickshell)" false;
    skwd.enable = mkBool "enable Skwd desktop shell (bar, launcher, music, notifications, settings, switcher) and skwd-daemon" false;
    hdr.enable = mkBool "enable HDR support (env vars for DXVK, Gamescope, Wine)" false;
    vicinae = {
      enable = mkBool "enable Vicinae (Wayland app runner + window switcher)" false;
      manageConfig = mkBool "let Nix manage vicinae theme/settings (disable for interactive config)" false;
    };
    iconTheme = lib.mkOption {
      type = types.str;
      default = "kora-pgrey";
      description = "Icon theme to apply system-wide (GTK + Qt).";
    };
    gtkTheme = lib.mkOption {
      type = types.enum [ "neg-gtk" "Flight-Dark-GTK" "Andromeda" "Flat-Remix-GTK-Blue-Darkest" ];
      default = "neg-gtk";
      description = "GTK theme to apply system-wide.";
    };
  };
}
