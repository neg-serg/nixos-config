{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.gui;
  # Module-shaped systemd user units (lib/systemd-user.nix)
  systemdUser = config.lib.neg.systemdUser;
in
lib.mkIf (cfg.enable or false) {
  systemd.user.services = {
    # Udiskie (Automounter)
    udiskie = systemdUser.mkUserService {
      presets = [
        "graphicalWanted"
        "restartOnFailure"
      ];
      description = "Udiskie automounter";
      serviceConfig = {
        ExecStart = "${lib.getExe' pkgs.udiskie "udiskie"} --no-tray"; # Removable disk automounter for udisks
        # Wayland-specific environment
        Environment = [
          "QT_QPA_PLATFORM=wayland"
          "XDG_SESSION_TYPE=wayland"
        ];
        RestartSec = "2";
      };
    };
  };

  # Restart quickshell when its config is redeployed: nh os switch restarts
  # the shell BEFORE nix-maid activation updates the config symlinks, so the
  # running shell keeps the OLD code until manually restarted. Watching the
  # shell.qml symlink catches the flip and reloads the new config.
  # Glass settings watchdog: the plugin drops its config on a compositor reload
  # and nothing reports it, so a timer checks every 10 s and re-applies only when
  # something drifted (the service is the check + conditional push).
  systemd.user.timers.hyprglass-watch = {
    description = "Check the hyprglass settings and repair them if needed";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "10s";
      Unit = "hyprglass-watch.service";
    };
  };

  # Re-apply the hyprglass settings when they are (re)deployed or when the Glass
  # panel writes overrides: the plugin only reads its config when it is pushed, so
  # without this a switch would leave the running session on the old glass until
  # the next login.
  systemd.user.paths.hyprglass-config = {
    description = "Push hyprglass settings when they change";
    wantedBy = [ "paths.target" ];
    pathConfig = {
      PathChanged = [
        "/home/neg/.config/hypr/hyprglass.lua"
        "/home/neg/.config/hypr/hyprglass.json"
      ];
      Unit = "hyprglass-apply.service";
    };
  };

  systemd.user.paths.quickshell-config = {
    description = "Restart quickshell when its config changes";
    wantedBy = [ "paths.target" ];
    pathConfig = {
      PathChanged = "/home/neg/.config/quickshell/shell.qml";
      Unit = "quickshell.service";
    };
  };
}
