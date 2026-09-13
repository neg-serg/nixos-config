{ ... }:
{
  networking.firewall = {
    enable = true;
    # sing-box LAN SOCKS5 proxy (0.0.0.0:10810, password auth): allow only from
    # private LAN ranges — the proxy is never reachable from the internet.
    # (extraCommands runs just before the final drop rule in the nixos-fw chain;
    # networking.firewall.extraInputRules is nftables-only in NixOS 26.05, and
    # switching the firewall backend to nftables would blacklist ip_tables and
    # risk podman/container networking — the iptables backend already runs on
    # the nf_tables kernel via iptables-nft.)
    extraCommands = builtins.readFile ../../../files/net/firewall-extra.sh;
  };

  boot.kernel.sysctl = {
    # Kernel-level rate limiting for ICMP responses (default is 1000ms = 1s, making it explicit/stricter is good)
    "net.ipv4.icmp_ratelimit" = 1000;
    "net.ipv4.icmp_ratemask" = 6168; # Default mask for destination unreachable, source quench, time exceeded, parameter problem
  };
}
