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
}
