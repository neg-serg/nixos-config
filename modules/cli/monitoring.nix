{
  lib,
  config,
  pkgs,
  ...
}:
{
  environment.systemPackages = lib.optionals (config.lib.neg.enabled "dev.bpf") [
    pkgs.below # time-traveling system monitor for Linux (BPF-based)
    pkgs.bpftrace # high-level tracing language for Linux eBPF
  ];
}
