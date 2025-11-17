##
# Module: system/kernel/sysctl
# Purpose: Network and security sysctls.
# Key options: none (static values).
# Dependencies: Applies to boot.kernel.sysctl.
{lib, ...}: {
  boot.kernel.sysctl = {
    "kernel.sysrq" = 0;

    # TCP hardening
    "net.ipv4.icmp_ignore_bogus_error_responses" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.secure_redirects" = 0;
    "net.ipv4.conf.default.secure_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.tcp_rfc1337" = 1;

    # TCP optimization
    "net.ipv4.tcp_fastopen" = 3;
    "net.ipv4.tcp_mtu_probing" = 1;
    # Provide sensible defaults that can be overridden by optional modules
    "net.ipv4.tcp_congestion_control" = lib.mkDefault "bbr";
    "net.core.default_qdisc" = lib.mkDefault "fq";
    "net.ipv4.tcp_max_syn_backlog" = lib.mkDefault 8192;

    # Socket and queue sizes
    "net.core.rmem_max" = 4194304;
    "net.core.wmem_max" = 4194304;
    "net.core.netdev_max_backlog" = 32768;
    "net.core.somaxconn" = 8192;
  };
}
