{...}: {
  imports = [
    ./logs
    ./loki
    ./netdata
    ./php-fpm-exporter
    ./promtail
    ./sysstat
    ./vnstat
    ./grafana
    ./pkgs
  ];
}
