{
  lib,
  pkgs,
  config,
  ...
}:
with lib;
  mkIf config.features.gui.enable (
    let
      # Import XDG helpers from repo root modules/lib
      xdg = import ../../../lib/xdg-helpers.nix {inherit pkgs;};
    in
      lib.mkMerge [
        # Note: Do not manage UWSM default-id here; allow uwsm to own
        # ~/.config/uwsm/default-id so it can be changed at runtime.
        # Provide a Wayland session entry that starts Hyprland via UWSM directly.
        # Some DMs list sessions from XDG data dirs; if supported, this entry will appear.
        (xdg.mkXdgDataText "wayland-sessions/hyprland-uwsm.desktop" ''
          [Desktop Entry]
          Name=Hyprland (UWSM)
          Comment=Hyprland via Universal Wayland Session Manager
          Exec=uwsm start hyprland
          TryExec=uwsm
          Type=Application
          DesktopNames=Hyprland
          X-GDM-Session-Type=wayland
          X-KDE-PluginInfo-Name=hyprland
          Keywords=wayland;wm;compositor;
        '')
        {xdg.dataFile."wayland-sessions/hyprland-uwsm.desktop".force = true;}
      ]
  )
