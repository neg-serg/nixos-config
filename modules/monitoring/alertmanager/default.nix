##
# Module: monitoring/alertmanager
# Purpose: Prometheus Alertmanager — routes Loki alert rules to Telegram via local webhook bridge.
# Ported from legacy Salt config (alertmanager.yml.j2).
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  cfg = config.monitoring.alertmanager or { };

  alertmanagerConfig = {
    global = { };
    route = {
      receiver = "telegram";
      group_by = [
        "alertname"
        "severity"
      ];
      group_wait = "10s";
      group_interval = "1m";
      repeat_interval = "1h";
    };
    receivers = [
      {
        name = "telegram";
        webhook_configs = [
          {
            url = "http://127.0.0.1:9094/alert";
            send_resolved = false;
            max_alerts = 20;
          }
        ];
      }
    ];
  };

  configFile = pkgs.writeText "alertmanager.yml" (builtins.toJSON alertmanagerConfig);
in
{
  options.monitoring.alertmanager = {
    enable = mkEnableOption "Enable Prometheus Alertmanager (routes Loki alerts).";

    port = mkOption {
      type = types.port;
      default = 9093;
      description = "Alertmanager web UI and API port.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Alertmanager listen address.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall for Alertmanager port.";
    };

    firewallInterfaces = mkOption {
      type = types.listOf types.str;
      default = [ "br0" ];
      description = "Interfaces to allow Alertmanager port on.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.alertmanager ];

    systemd.services.alertmanager = {
      description = "Prometheus Alertmanager";
      documentation = [ "https://prometheus.io/docs/alerting/latest/alertmanager/" ];
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.alertmanager} --config.file=${configFile} --web.listen-address=${cfg.listenAddress}:${toString cfg.port} --storage.path=/var/lib/alertmanager --data.retention=120h";
        Restart = "on-failure";
        RestartSec = 5;
        StateDirectory = "alertmanager";
        DynamicUser = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        CapabilityBoundingSet = "";
        SystemCallFilter = "@system-service";
      };
    };

    systemd.tmpfiles.rules = lib.mkAfter [
      "d /var/lib/alertmanager 0750 alertmanager alertmanager - -"
    ];

    networking.firewall.interfaces = mkIf cfg.openFirewall (
      lib.genAttrs cfg.firewallInterfaces (_iface: {
        allowedTCPPorts = [ cfg.port ];
      })
    );
  };
}
