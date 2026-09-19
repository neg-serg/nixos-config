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
        # The app is an MPD remote control with no authentication, so it is
        # pinned to the loopback interface (the package patches in a HOST
        # override, defaulting to 127.0.0.1). systemd's own IPAddressDeny cannot
        # do it here: for a user unit it is refused with "unit configures an IP
        # firewall, but not running as root".
        Environment = [
          "PORT=${toString port}"
          "HOST=127.0.0.1"
        ];
        Restart = "on-failure";
        RestartSec = "2";
      };
    };
  };
}
