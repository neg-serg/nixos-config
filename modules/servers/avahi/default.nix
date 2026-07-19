##
# Module: servers/avahi
# Purpose: Avahi (mDNS) profile for local discovery.
# Key options: cfg = config.servicesProfiles.avahi.enable
# Dependencies: services.avahi.
{
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (lib.strings) escapeXML;
  cfg = config.servicesProfiles.avahi or { enable = false; };

  mkServiceXML = { name, type, port, txtRecords ? [] }:
    let
      txtLines = map (r: "        <txt-record>${escapeXML r}</txt-record>") txtRecords;
    in ''
      <?xml version="1.0" standalone='no'?>
      <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
      <service-group>
        <name replace-wildcards="yes">%h ${escapeXML name}</name>
        <service>
          <type>_${escapeXML type}._tcp</type>
          <port>${toString port}</port>${lib.optionalString (txtLines != []) "\n${lib.concatStringsSep "\n" txtLines}"}
        </service>
      </service-group>
    '';
in
{
  options.servicesProfiles.avahi.services = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        name = lib.mkOption { type = lib.types.str; description = "Service name"; };
        type = lib.mkOption { type = lib.types.str; description = "Service type sans _tcp"; };
        port = lib.mkOption { type = lib.types.port; description = "TCP port"; };
        txtRecords = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "TXT record values";
        };
      };
    });
    default = [];
    description = "Avahi mDNS services to publish";
  };

  config = lib.mkIf cfg.enable {
    services.avahi = {
      enable = true;
      nssmdns4 = true; # Needed for mDNS (IPv4)
      nssmdns6 = true; # Enable mDNS for IPv6
      openFirewall = true;
      publish = {
        enable = true;
        userServices = true;
        workstation = true;
      };
    };

    # Published mDNS services from structured data
    environment.etc = lib.listToAttrs (map (svc: {
      name = "avahi/services/${svc.name}.service";
      value.text = mkServiceXML svc;
    }) cfg.services);

    systemd.services.avahi-daemon.serviceConfig = {
      # Hardening (keep default capabilities — avahi needs CAP_SETUID + CAP_SETGID)
      ProtectSystem = "strict";
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };
}
