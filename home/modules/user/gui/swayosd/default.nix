{
  lib,
  config,
  ...
}:
with lib;
  mkIf (config.features.gui.enable or false) {
    services.swayosd.enable = true;

    systemd.user.services.swayosd-libinput-backend = {
      Unit = {
        Description = "SwayOSD LibInput Backend";
        PartOf = ["graphical-session.target"];
        After = ["graphical-session.target"];
      };
      Service = {
        ExecStart = "${lib.getExe' pkgs.swayosd "swayosd-libinput-backend"}";
        Restart = "always";
      };
      Install = {
        WantedBy = ["graphical-session.target"];
      };
    };
  }
