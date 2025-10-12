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
      "listen.group" = "nextcloud";
      "listen.mode" = "0660";
    };
  };
}
