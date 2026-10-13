##
# Module: nix-maid/sys/wallpaper-workspaces
# Purpose: one wallpaper per Hyprland workspace.
#
# `wl` paints per *output*; the helper in packages/local-bin/bin/wl-workspaces.py
# (deployed as ~/.local/bin/wl-workspaces) watches Hyprland's event socket and
# repaints an output with `wl img --no-notify` when its active workspace
# changes. Assignments are a seeded, persisted mapping (see files/wl/
# workspaces.toml for the knobs) — no per-workspace state in the compositor.
#
# The greeter keeps following the wallpaper the *user* picked: swaps carry
# --no-notify and leave a marker that wl-state-sync (see wallpaper-sync.nix)
# skips, so neither ~/.cache/quickshell-wallpaper-path nor the greeter cache
# flaps on workspace changes. `wl-workspaces shuffle` (the Super+Shift+C
# wallpaper keybind) starts a new set for the session.
{
  lib,
  config,
  pkgs,
  neg,
  ...
}:
let
  cfg = config.features.gui;
  systemdUser = config.lib.neg.systemdUser;

  # The script itself is deployed by nix-maid (cli/local-bin.nix renders every
  # file in packages/local-bin/bin); the unit calls the deployed copy with an
  # explicit interpreter, so the service needs no PATH of its own.
  script = "${config.lib.neg.homeDir}/.local/bin/wl-workspaces";
  python = lib.getExe pkgs.python3;
in
lib.mkIf (cfg.enable or false) (
  lib.mkMerge [
    (neg.mkHomeFiles {
      # Live link: tuning the mapping (a new pool, a per-workspace pin) does not
      # need a rebuild — but the watcher loads the file once at startup, so
      # restart wl-workspaces.service after editing (one-shots read it per run).
      ".config/wl/workspaces.toml".source = config.lib.neg.live "files/wl/workspaces.toml";
    })

    {
      systemd.user.services."wl-workspaces" = systemdUser.mkUserService {
        presets = [
          "graphicalSession"
          "restartOnFailure"
        ];
        description = "Per-workspace wallpapers (wl img on workspace changes)";
        # The daemon owns the surfaces; painting before it is up would just fail.
        after = [ "wl-daemon.service" ];
        wants = [ "wl-daemon.service" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${python} ${script} watch";
          RestartSec = 3;
          Environment = [
            "WL_WORKSPACES_WL=${pkgs.wl}/bin/wl"
            "WL_WORKSPACES_HYPRCTL=/run/current-system/sw/bin/hyprctl"
          ];
        };
      };
    }
  ]
)
