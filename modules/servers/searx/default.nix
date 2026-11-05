##
# Module: servers/searx
# Purpose: SearXNG self-hosted metasearch, bound to localhost as the default
#          privacy-first search for Vivaldi.
# Key options: cfg = config.servicesProfiles.searx.enable
# Secret: sops secrets/home/searxng.sops.yaml["searxng-secret"] = a single
#         "SEARX_SECRET_KEY=<value>" line (read via services.searx.environmentFile).
{
  lib,
  config,
  ...
}:
let
  cfg = config.servicesProfiles.searx or { enable = false; };
in
{
  config = lib.mkIf cfg.enable {
    # systemd (root) reads EnvironmentFile, so a root-owned 0400 sops secret
    # is fine for this system service.
    sops.secrets."searxng-secret" = {
      sopsFile = config.lib.neg.path "secrets/home/searxng.sops.yaml";
      owner = "root";
      mode = "0400";
    };

    services.searx = {
      enable = true;
      # File content must be: SEARX_SECRET_KEY=<value>  (see sops entry above).
      environmentFile = config.sops.secrets."searxng-secret".path;
      settings = {
        server = {
          secret_key = "@SEARX_SECRET_KEY@";
          bind_address = "127.0.0.1";
          port = 7777;
          # Localhost-only instance behind no reverse proxy: botdetection would
          # log "X-Forwarded-For nor X-Real-IP header is set!" on every request.
          limiter = false;
        };
        search = {
          formats = [
            "html"
            "json"
          ];
        };
        # torch and ahmia need a Tor proxy that is not configured here, so they
        # fail at startup and flood the journal ("set engine to inactive").
        engines = [
          {
            name = "torch";
            disabled = true;
          }
          {
            name = "ahmia";
            disabled = true;
          }
        ];
      };
    };
  };
}
