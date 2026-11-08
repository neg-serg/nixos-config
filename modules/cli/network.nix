{
  pkgs,
  ...
}:
{
  environment.systemPackages = [
    # Network diagnostics
    pkgs.urlscan # extract URLs from text blobs
    pkgs.whois # domain info lookup
    pkgs.neg.oryx # TUI traffic sniffer using eBPF (run with sudo; needs BTF kernel)
    pkgs.netwatch # TUI network diagnostics (per-connection process view; sudo for capture)
    # Remote access
    pkgs.neg.dnsglobe # TUI: watch one DNS record propagate across 34 public resolvers on a world map
    pkgs.xxh # SSH wrapper for jumping into remote shells
  ];

}
