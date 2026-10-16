##
# Module: servers/koito
# Purpose: Koito self-hosted scrobbler, bound to loopback. Serves as the local
#          scrobble hub: features.media.audio.listenbrainzMpd can submit here
#          (apiUrl = http://127.0.0.1:<port>) instead of listenbrainz.org, and
#          Koito can relay listens onwards.
# Key options: cfg = config.servicesProfiles.koito.{enable,port}
# Secret: none required to start — create the first account in the web UI
#         (http://127.0.0.1:<port>); the account's API key goes into the client.
{
  lib,
  config,
  ...
}:
let
  cfg =
    config.servicesProfiles.koito or {
      enable = false;
      port = 4110;
    };

  # Module-shaped systemd units (lib/systemd-user.nix)
  systemdUser = config.lib.neg.systemdUser;
in
{
  config = lib.mkIf cfg.enable {
    services.koito = {
      enable = true;
      environment = {
        KOITO_BIND_ADDR = "127.0.0.1";
        KOITO_LISTEN_PORT = cfg.port;
      };
    };

    # The nixpkgs unit ships no restart policy, so a crash would leave the hub
    # dead. The policy comes from the restartOnFailure preset; the delay stays
    # at the call site. Restart=on-failure also puts koito on the radar of the
    # crash-loop scanner in hosts/trantor/notify-crashloop.nix (it only
    # considers units systemd is configured to auto-restart).
    systemd.services.koito = systemdUser.mkSystemService {
      presets = [ "restartOnFailure" ];
      serviceConfig = {
        RestartSec = 10;
      };
    };
  };
}
