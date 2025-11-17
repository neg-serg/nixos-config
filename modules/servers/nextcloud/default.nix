##
# Module: servers/nextcloud
# Purpose: Nextcloud profile; optional nginx/caddy imports.
# Key options: cfg = config.servicesProfiles.nextcloud.enable
# Dependencies: pkgs.nextcloud*, sops (admin-pass), reverse proxy submodules.
{
  lib,
  config,
  pkgs,
  ...
}: let
  hasNcSecret = builtins.pathExists (../../.. + "/secrets/nextcloud.sops.yaml");
  cfg = config.servicesProfiles.nextcloud or {enable = false;};
  chosenPackage =
    if (cfg ? package) && cfg.package != null
    then cfg.package
    else pkgs.nextcloud32;
in {
  # Optional: nginx reverse proxy + ACME integration (guarded by an enable flag)
  imports = [./nginx.nix ./caddy.nix];

  config = lib.mkIf cfg.enable {
    # Register SOPS secret only if the file exists to avoid eval errors
    sops.secrets."nextcloud/admin-pass" = lib.mkIf hasNcSecret {
      sopsFile = ../../../secrets/nextcloud.sops.yaml;
    };

    services.nextcloud = {
      enable = true;
      package = chosenPackage;
      # Default to localhost; override to a FQDN when exposing externally
      hostName = lib.mkDefault "localhost";
      database.createLocally = true;
      configureRedis = true;
      datadir = "/nextcloud";
      config =
        {
          adminuser = "init";
          dbtype = "mysql";
        }
        // (lib.optionalAttrs hasNcSecret {
          adminpassFile = config.sops.secrets."nextcloud/admin-pass".path;
        });
    };

    # Explicitly override PHP-FPM pool settings for Nextcloud
    services.phpfpm.pools.nextcloud.settings = {
      "listen.owner" = "nextcloud";
      # Use a shared web group so both Caddy and Prometheus exporter can access the socket
      "listen.group" = "nginx";
      "listen.mode" = "0660";
      # Enable status endpoint so php-fpm exporter can scrape via unix socket
      "pm.status_path" = "/status";
    };

    # Shared web group and memberships for socket access
    # - Provide the nginx group even when nginx service is disabled
    # - Add caddy to the group so it can read the php-fpm socket
    # - Prometheus user membership is managed by the php-fpm exporter module when that exporter is enabled
    users.groups.nginx = lib.mkDefault {};
    users.users.caddy.extraGroups = ["nginx"];
  };
}
