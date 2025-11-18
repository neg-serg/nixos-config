{
  lib,
  pkgs,
  config,
  iwmenuProvider ? null,
  ...
}:
with lib;
  mkIf config.features.gui.enable (
    let
      # Import XDG helpers from repo root modules/lib
      xdg = import ../../../lib/xdg-helpers.nix {inherit pkgs;};
      devSpeed = config.features.devSpeed.enable or false;
      groups = {
        core =
          [
            pkgs.dragon-drop # drag-n-drop from console
            pkgs.gowall # generate palette from wallpaper
            pkgs.grimblast # Hyprland screenshot helper
            # Base screenshot/input helpers (grim, slurp, wtype, wl-clipboard) now provided system-wide.
            pkgs.swww # Wayland wallpaper daemon
            pkgs.waybar # Wayland status bar
            pkgs.waypipe # Wayland remoting (ssh -X like)
            pkgs.wev # xev for Wayland
            pkgs.wf-recorder # screen recording
            pkgs.wl-clip-persist # persist clipboard across app exits
          ]
          ++ lib.optionals (pkgs ? uwsm) [pkgs.uwsm];
        extras = lib.optionals (! devSpeed && (iwmenuProvider != null)) [
          (iwmenuProvider pkgs) # Wayland app launcher/menu from flake input
        ];
      };
      flags = {
        core = true;
        extras = true;
      };
    in
      lib.mkMerge [
        {
          home.packages = config.lib.neg.pkgsList (config.lib.neg.mkEnabledList flags groups);
        }
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
