{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.media.audio.solaMpd;
  systemdUser = config.lib.neg.systemdUser;

  # The backend serves the built UI and talks to MPD itself (the browser only
  # speaks to this one origin), so it is enough to run the server and open the
  # address. It is bound to the loopback interface by the app itself.
  port = cfg.port;
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.sola-mpd # browser MPD client: Node backend + React UI, served on loopback
    ];

    systemd.user.services.sola-mpd = systemdUser.mkUserService {
      description = "Sola MPD — browser MPD client (backend + web UI)";
      presets = [ "defaultWanted" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.sola-mpd}";
        Environment = [ "PORT=${toString port}" ];
        Restart = "on-failure";
        RestartSec = "2";
      };
    };
  };
}
