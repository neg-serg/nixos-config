##
# Module: monitoring/php-fpm-exporter
# Purpose: Harden and order the Prometheus PHP-FPM exporter to work with Nextcloud's unix socket.
# Implements AGENTS tips:
#  - Allow AF_UNIX in sandbox, add nginx group, run as prometheus (not DynamicUser)
#  - Start after Nextcloud PHP-FPM pool to avoid early failures
{
  lib,
  config,
  ...
}: let
  inherit (lib) mkAfter mkDefault mkIf mkForce optionals;
  exporterEnabled = config.services.prometheus.exporters."php-fpm".enable or false;
  nextcloudEnabled = config.services.nextcloud.enable or false;
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
    systemd.services."prometheus-php-fpm-exporter" = {
      # Order after Nextcloud PHP-FPM components when present
      after = optionals nextcloudEnabled [
        "phpfpm-nextcloud.service"
        "phpfpm.service"
        "nextcloud-setup.service"
      ];
      wants = optionals nextcloudEnabled ["phpfpm-nextcloud.service"];
      serviceConfig = {
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
  };
}
