##
# Module: system/net/bbrv3
# Purpose: Enable TCP BBRv3 congestion control for reduced latency and improved throughput.
# BBRv3 is built into Linux 6.18+ (tcp_bbr module). This module ensures it's loaded
# and set as the active congestion control algorithm.
{ lib, config, ... }:
{
  config = lib.mkIf (config.features.net.bbrv3.enable or false) {
    boot.kernelModules = [ "tcp_bbr" ];

    boot.kernel.sysctl = {
      # BBRv3 with fq qdisc for pacing: best latency/throughput balance for desktop/gaming
      "net.ipv4.tcp_congestion_control" = lib.mkForce "bbr";
      # fq (Fair Queue) qdisc is required for BBR pacing
      "net.core.default_qdisc" = lib.mkForce "fq";
    };
  };
}
