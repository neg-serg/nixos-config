##
# Module: monitoring/php-fpm-exporter
# Purpose: Harden and order the Prometheus PHP-FPM exporter for unix-socket PHP-FPM pools.
{
  lib,
  config,
  ...
}: let
  inherit (lib) mkAfter mkDefault mkIf mkForce;
  exporterEnabled = config.services.prometheus.exporters."php-fpm".enable or false;
in {
  config = mkIf exporterEnabled {
    # Ensure the shared web group exists and prometheus joins it for socket access
    users = {
      groups.nginx = mkDefault {};
      groups.prometheus = mkDefault {};
      users.prometheus = {
        isSystemUser = mkDefault true;
        group = mkDefault "prometheus";
        home = mkDefault "/var/lib/prometheus";
        extraGroups = mkAfter ["nginx"];
      };
    };

    # Systemd unit adjustments for php-fpm exporter
    systemd.services."prometheus-php-fpm-exporter".serviceConfig = {
      # Use stable prometheus user to inherit static groups
      DynamicUser = mkForce false;
      User = mkForce "prometheus";
      Group = mkForce "prometheus";
      # Allow connecting to php-fpm via unix socket and ensure group access
      SupplementaryGroups = ["nginx"];
      RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
