{ ... }:
{
  networking.firewall = {
    enable = true;
    # Hardening: Limit ICMP Echo Request (ping) to prevent flood
    # 1 per second, burst of 5. Drops excess.
    extraCommands = ''
      # Flush old rules (optional, but good for idempotency if reloading manually)
      # iptables -D nixos-fw -p icmp --icmp-type echo-request -j DROP 2>/dev/null || true

      # Limit Ping
      iptables -A nixos-fw -p icmp --icmp-type echo-request -m limit --limit 1/second --limit-burst 5 -j ACCEPT
      iptables -A nixos-fw -p icmp --icmp-type echo-request -j DROP
    '';
  };

  boot.kernel.sysctl = {
    # Kernel-level rate limiting for ICMP responses (default is 1000ms = 1s, making it explicit/stricter is good)
    "net.ipv4.icmp_ratelimit" = 1000;
    "net.ipv4.icmp_ratemask" = 6168; # Default mask for destination unreachable, source quench, time exceeded, parameter problem
  };
}
