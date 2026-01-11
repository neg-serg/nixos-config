{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.below # time-traveling system monitor for Linux (BPF-based)
    pkgs.bpftrace # high-level tracing language for Linux eBPF
    pkgs.goaccess # real-time web log analyzer and interactive viewer
    pkgs.kmon # Linux kernel management and monitoring TUI
    pkgs.lnav # Log File Navigator - advanced log viewer for terminal
    pkgs.viddy # modern alternative to watch command with time-travel and diffs
    pkgs.zfxtop # system monitor with focus on process grouping and ZFX style
  ];
}
