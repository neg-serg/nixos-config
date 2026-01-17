{
  pkgs,
  lib,
  config,
  ...
}:
{
  environment.systemPackages = [
    pkgs.goaccess # real-time web log analyzer and interactive viewer
    pkgs.kmon # Linux kernel management and monitoring TUI
    pkgs.zfxtop # system monitor with focus on process grouping and ZFX style
  ]
  ++ (lib.optionals (config.features.dev.bpf.enable or false) [
    pkgs.below # time-traveling system monitor for Linux (BPF-based)
    pkgs.bpftrace # high-level tracing language for Linux eBPF
    pkgs.neg.bpf_host_latency # BCC DNS latency tracer; deeper insight than dig/tcpdump
  ]);
}
