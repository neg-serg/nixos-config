{ lib, mkBool, ... }:
{
  options.features.gui = {
    enable = mkBool "enable GUI stack (wayland/hyprland, quickshell, etc.)" true;
    qt.enable = mkBool "enable Qt integrations for GUI (hyprqt6engine, qt6ct fallback, hyprland-qt-*)" true;
    quickshell = {
      enable = mkBool "enable Quickshell (panel) at login" true;
    };
    pleamar = {
      enable = mkBool "enable the pleamar shell at login" false;
    };
    # Looped video wallpaper (mpv in a hyprwinwrap-pinned window). Off by
    # default: wl-daemon owns the background layer, and a pinned full-screen
    # window covers it — the two wallpaper systems do not compose.
    # Submodule shape like every other flag: lib.neg.enabled reads
    # features.<path>.enable, and a flat mkBool made this one impossible to turn
    # on (x.enable or false swallowed the type error into false).
    wallpaperVideo = {
      enable = mkBool "enable the looped video wallpaper window (mpv + hyprwinwrap)" false;
    };
    # Swatch-deck wallpaper picker: a standalone Quickshell config (`qs -p
    # ~/.config/qs-wallpaperpicker`), so it runs beside the bar instead of
    # replacing it. Which folder it browses and which program paints the chosen
    # picture is the settings seed owned by
    # modules/user/nix-maid/gui/wallpaper-picker.nix (`wl img {}` on trantor).
    wallpaperPicker = {
      enable = mkBool "enable the Quickshell wallpaper picker (qs-wallpaperpicker)" false;
      # wl-daemon keeps painting the desktop background; the picker hands it every
      # image (the gear's `wl img {}`) and paints only what wl cannot — animated
      # GIF/WebP and videos — on a layer above wl's, under every window. See
      # modules/user/nix-maid/gui/wallpaper-picker.nix.
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
    # sonda: a file manager whose search knows what the files hold (pleamar scene window,
    # EmbeddingGemma 2 on llama.cpp). The package is packages/sonda; the models arrive on first
    # `sonda setup` (865 MB into $XDG_DATA_HOME), see modules/user/nix-maid/gui/sonda.nix.
    sonda = {
      enable = mkBool "enable sonda (file manager searching files by content)" false;
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
