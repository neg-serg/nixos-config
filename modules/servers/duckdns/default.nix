##
# Module: servers/duckdns
# Purpose: Wire servicesProfiles.duckdns to the Nyx DuckDNS module.
# Key options: cfg = config.servicesProfiles.duckdns (enable, domain, environmentFile, ipv6.*, certs.*)
# Dependencies: inputs.nyx.nixosModules.duckdns (chaotic.duckdns.*)
{
  lib,
  config,
  inputs,
  ...
}:
let
  cfg = config.servicesProfiles.duckdns or { enable = false; };
in
{
  imports = [ ];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.domain != "";
        message = "Set servicesProfiles.duckdns.domain to your DuckDNS hostname (e.g., example.duckdns.org).";
      }
      {
        assertion = cfg.environmentFile != "";
        message = "servicesProfiles.duckdns.environmentFile must point to an EnvironmentFile containing DUCKDNS_TOKEN.";
      }
    ];

    chaotic.duckdns = {
      enable = true;
      inherit (cfg) domain environmentFile onCalendar;
      ipv6 = {
        enable = cfg.ipv6.enable;
        device = cfg.ipv6.device;
      };
      certs = {
        enable = cfg.certs.enable;
        useHttpServer = cfg.certs.useHttpServer;
        group = cfg.certs.group;
        httpPort = cfg.certs.httpPort;
      };
    };
  };
}
