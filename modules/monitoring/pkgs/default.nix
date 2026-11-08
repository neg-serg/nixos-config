{
  config,
  pkgs,
  ...
}:
let
  onDemand = config.lib.neg.onDemand pkgs;
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
    pkgs.iotop # top for iops
    pkgs.iperf # modern iperf3 bandwidth measurement
    (onDemand {
      name = "perf";
      attr = "perf";
    }) # linux perf tooling, built on first call
    pkgs.bandwhich # real-time per-process and per-connection bandwidth monitor
    # Per-IP traffic monitor (TUI, run with sudo). The launcher builds it on
    # first call — as root the first time, into /root/.local/state/nix-apps.
    (onDemand {
      name = "tmd-top";
      attr = "tmd-top";
    })
    pkgs.adguardian # terminal dashboard for AdGuard Home
    pkgs.sysstat # sar, iostat, mpstat, pidstat and friends
    pkgs.vmtouch # portable file system cache diagnostics and control
    pkgs.hxtools # misc hx* admin/git/media utilities (hxnetload, git-forest, qplay)
  ];
}
