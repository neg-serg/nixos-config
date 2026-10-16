{ lib, mkBool, ... }:
{
  options.features.gui = {
    enable = mkBool "enable GUI stack (wayland/hyprland, quickshell, etc.)" true;
    qt.enable = mkBool "enable Qt integrations for GUI (hyprqt6engine, qt6ct fallback, hyprland-qt-*)" true;
    quickshell = {
      enable = mkBool "enable Quickshell (panel) at login" true;
    };
    dms = {
      enable = mkBool "install DankMaterialShell (DankLinux shell) for on-demand trial, without autostart" false;
    };
    pleamar = {
      enable = mkBool "enable the pleamar shell at login" false;
    };
    hdr.enable = mkBool "enable HDR support (env vars for DXVK, Gamescope, Wine)" false;
    hyprwhspr.enable = mkBool "enable hyprwhspr-rs (local whisper.cpp voice dictation for Hyprland)" false;
    hyprKdeconnect.enable = mkBool "enable hypr-kdeconnect-fix (RemoteDesktop portal backend feeding KDE Connect/Deskflow input into Hyprland's virtual-input protocols)" true;
    vicinae = {
      enable = mkBool "enable Vicinae (Wayland app runner + window switcher)" false;
      manageConfig = mkBool "let Nix manage vicinae theme/settings (disable for interactive config)" false;
    };
    atrium = {
      enable = mkBool "enable atrium (Wayland multiseat display manager)" false;
    };
    iconTheme = lib.mkOption {
      type = lib.types.str;
      default = "kora-pgrey";
      description = "Icon theme to apply system-wide (GTK + Qt).";
    };
    gtkTheme = lib.mkOption {
      type = lib.types.enum [
        "neg-gtk"
        "Flight-Dark-GTK"
        "Andromeda"
        "Flat-Remix-GTK-Blue-Darkest"
      ];
      default = "neg-gtk";
      description = "GTK theme to apply system-wide.";
    };
  };
}
