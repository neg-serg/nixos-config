{
  lib,
  config,
  ...
}: let
  nc = config.services.nextcloud;
  cfg = config.services.nextcloud.nginxProxy;
  domain = nc.hostName or "localhost";
in {
  options.services.nextcloud.nginxProxy.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Enable nginx reverse proxy and Let's Encrypt (ACME) for Nextcloud.
      Requires `services.nextcloud.hostName` to be a reachable DNS name.
    '';
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = domain != "localhost";
        message = "Set services.nextcloud.hostName to a public or LAN DNS name when enabling nginxProxy.";
      }
    ];

    # Open HTTP/HTTPS for ACME + clients
    networking.firewall.allowedTCPPorts = [80 443];

    # Accept LE terms; set a real email to receive expiry notices
    security.acme = {
      acceptTerms = true;
      defaults.email = lib.mkDefault "change-me@example.com";
    };

    services.nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      # Allow large uploads
      clientMaxBodySize = "2g";
      virtualHosts.${domain} = {
        forceSSL = true;
        enableACME = true;
      };
    };
  };
}
