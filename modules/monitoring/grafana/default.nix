##
# Module: monitoring/grafana
# Purpose: Grafana with a preprovisioned Loki datasource. LAN-exposed with per-interface firewall.
# Key options: monitoring.grafana.enable, monitoring.grafana.port, monitoring.grafana.listenAddress,
#              monitoring.grafana.openFirewall, monitoring.grafana.firewallInterfaces
{ lib, config, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.monitoring.grafana or {};
  lokiPort = config.monitoring.loki.port or 3100;
  lokiUrl = "http://127.0.0.1:${toString lokiPort}";
in {
  options.monitoring.grafana = {
    enable = mkEnableOption "Enable Grafana with Loki datasource.";

    port = mkOption {
      type = types.port;
      default = 3030; # avoid conflict with AdGuardHome on :3000
      description = "Grafana HTTP port.";
    };

    # Admin credentials
    adminUser = mkOption {
      type = types.str;
      default = "admin";
      description = "Grafana admin username.";
    };
    adminPasswordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to a file containing the Grafana admin password (use with SOPS).";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Grafana HTTP listen address.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall for Grafana port on selected interfaces.";
    };

    firewallInterfaces = mkOption {
      type = types.listOf types.str;
      default = [ "br0" ];
      description = "Interfaces where Grafana port is allowed when openFirewall is true.";
    };

    caddyProxy = {
      enable = mkEnableOption "Serve Grafana via Caddy with HTTPS (TLS internal).";
      domain = mkOption {
        type = types.str;
        default = let hn = config.networking.hostName or "telfir"; in "grafana." + hn;
        description = "Domain name to serve Grafana on via Caddy.";
      };
      tlsInternal = mkOption {
        type = types.bool;
        default = true;
        description = "Use Caddy internal CA for LAN HTTPS.";
      };
      openFirewall = mkOption {
        type = types.bool;
        default = true;
        description = "Open firewall for 80/443 when proxying via Caddy.";
      };
      firewallInterfaces = mkOption {
        type = types.listOf types.str;
        default = [ "br0" ];
        description = "Interfaces where 80/443 are allowed when openFirewall is true.";
      };
    };
  };

  config = mkIf (cfg.enable or false) {
    services.grafana = {
      enable = true;
      settings.server = {
        http_port = cfg.port;
        http_addr = cfg.listenAddress;
        domain = config.networking.hostName or "grafana.local";
      };
      settings.security = {
        admin_user = cfg.adminUser;
      } // (lib.optionalAttrs (cfg.adminPasswordFile != null) {
        admin_password = "${"$"}__file{${cfg.adminPasswordFile}}";
      });
      # Provision a Loki datasource so Explore works out of the box
      provision = {
        enable = true;
        datasources.settings.datasources = [
          {
            name = "Loki";
            type = "loki";
            access = "proxy";
            url = lokiUrl;
            isDefault = true;
            jsonData = { }; # keep minimal
          }
        ];
      };
    };

    # Per-interface firewall openings (Grafana port and, optionally, Caddy proxy ports)
    networking.firewall.interfaces = lib.mkMerge [
      (mkIf cfg.openFirewall (
        lib.genAttrs cfg.firewallInterfaces (iface: { allowedTCPPorts = [ cfg.port ]; })
      ))
      (mkIf (cfg.caddyProxy.enable && cfg.caddyProxy.openFirewall) (
        lib.genAttrs cfg.caddyProxy.firewallInterfaces (iface: { allowedTCPPorts = [ 80 443 ]; })
      ))
    ];

    # Optional: Caddy reverse proxy with HTTPS
    # Opens 80/443 per-interface and sets up a vhost that proxies to Grafana
    # on localhost:port with TLS internal for LAN trust.
    services.caddy = mkIf cfg.caddyProxy.enable {
      enable = true;
      virtualHosts."${cfg.caddyProxy.domain}".extraConfig = ''
        encode zstd gzip
        header {
          Strict-Transport-Security "max-age=15768000; includeSubDomains; preload"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "SAMEORIGIN"
          Referrer-Policy "no-referrer"
          Permissions-Policy "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), midi=(), payment=(), usb=(), fullscreen=(self), picture-in-picture=(self)"
        }
        reverse_proxy 127.0.0.1:${toString cfg.port}
        ${lib.optionalString cfg.caddyProxy.tlsInternal "tls internal"}
        handle /ca.crt {
          root * /var/lib/caddy
          file_server
        }
      '';
    };

    # nothing else
  };
}
