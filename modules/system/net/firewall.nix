{ ... }:
{
  networking.firewall = {
    enable = true;
  };

  boot.kernel.sysctl = {
    # Kernel-level rate limiting for ICMP responses (default is 1000ms = 1s, making it explicit/stricter is good)
    "net.ipv4.icmp_ratelimit" = 1000;
    "net.ipv4.icmp_ratemask" = 6168; # Default mask for destination unreachable, source quench, time exceeded, parameter problem
  };
}
