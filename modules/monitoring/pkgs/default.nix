{
  lib,
  pkgs,
  config,
  ...
}:
let
  rolesMonitoringEnabled = config.roles.monitoring.enable or false;
in
{
  programs = {
    mtr = {
      enable = true;
    };
  };
  environment.systemPackages = [
    pkgs.atop # system and process monitor with logging
    pkgs.btop # even more fancy top
    pkgs.dool # example use: dool -cdnpmgs --top-bio --top-cpu --top-mem (dstat is not supported as standalone tool anymore)
    pkgs.iotop # top for iops
    pkgs.iperf # modern iperf3 bandwidth measurement
    pkgs.iperf2 # IP bandwidth measurement
    pkgs.perf # linux profile tools
    pkgs.linuxPackages_latest.turbostat # cpu monitor
    pkgs.nethogs # network traffic per process
    pkgs.adguardian # terminal dashboard for AdGuard Home
    pkgs.powertop # watch for power events
    pkgs.procdump # procdump for linux
    pkgs.sysstat # sar, iostat, mpstat, pidstat and friends
    pkgs.vmtouch # portable file system cache diagnostics and control
  ]
  ++ lib.optionals rolesMonitoringEnabled [
    pkgs.hxtools # misc hx* admin/git/media utilities (hxnetload, git-forest, qplay)
  ];
}
