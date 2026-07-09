##
# Module: system/kernel/sysctl-gaming
# Purpose: Gaming-optimized sysctl parameters for lower latency and reduced jitter.
# Key options: gated behind profiles.performance.enable
{ lib, config, ... }:
{
  config = lib.mkIf (config.profiles.performance.enable or false) {
    boot.kernel.sysctl = {
      # Reduce swap readahead (pages per swap read) — less IO jitter during gaming
      # RISK: 0 is only safe because swap is disabled on this system. If swap is ever
      # re-enabled, this MUST be raised (default 3) — otherwise each page fault does
      # single-page I/O, causing extreme thrashing under memory pressure.
      "vm.page-cluster" = 0;
      # Optimize TCP for low latency over throughput (benefits online gaming)
      "net.ipv4.tcp_low_latency" = 1;
      # Socket busy polling: 50 microseconds spin before sleeping (reduces network latency)
      # NOTE: This only takes effect for applications that opt in via the SO_BUSY_POLL socket
      # option. Low-latency apps (games with custom networking, some RPC frameworks) benefit;
      # most apps are unaffected. Trade-off: marginally higher CPU use on polled sockets.
      "net.core.busy_poll" = 50;
    };
  };
}
