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
  };
}
