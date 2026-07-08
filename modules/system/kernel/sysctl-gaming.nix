##
# Module: system/kernel/sysctl-gaming
# Purpose: Gaming-optimized sysctl parameters for lower latency and reduced jitter.
# Key options: gated behind profiles.performance.enable
{ lib, config, ... }:
{
  config = lib.mkIf (config.profiles.performance.enable or false) {
    boot.kernel.sysctl = {
      # Reduce swap readahead — less IO jitter during gaming
      "vm.page-cluster" = 0;
      # Optimize TCP for low latency over throughput (benefits online gaming)
      "net.ipv4.tcp_low_latency" = 1;
      # Socket busy polling: 50 microseconds polling before sleeping (lower network latency)
      "net.core.busy_poll" = 50;
    };
  };
}
