{pkgs, ...}: {
  programs = {
    mtr = {enable = true;};
  };
  environment.systemPackages = [
    pkgs.atop # system and process monitor with logging
    pkgs.bcc # eBPF tracing toolkit (BCC) utilities
    pkgs.btop # even more fancy top
    pkgs.dool # example use: dool -cdnpmgs --top-bio --top-cpu --top-mem (dstat is not supported as standalone tool anymore)
    pkgs.iotop # top for iops
    pkgs.iperf
    pkgs.iperf2 # IP bandwidth measurement
    pkgs.perf # linux profile tools
    pkgs.linuxPackages_latest.turbostat # cpu monitor
    pkgs.nethogs # network traffic per process
    pkgs.powertop # watch for power events
    pkgs.procdump # procdump for linux
    pkgs.sysstat # sar, iostat, mpstat, pidstat and friends
    pkgs.vmtouch # portable file system cache diagnostics and control
  ];
}
