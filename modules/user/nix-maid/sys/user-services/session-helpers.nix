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
  systemd.user.paths.quickshell-config = {
    description = "Restart quickshell when its config changes";
    wantedBy = [ "paths.target" ];
    pathConfig = {
      PathChanged = "/home/neg/.config/quickshell/shell.qml";
      Unit = "quickshell.service";
    };
  };
}
