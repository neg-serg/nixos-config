{
  pkgs,
  ...
}:
{
  environment.systemPackages = [
    # Network diagnostics
    pkgs.prettyping # fancy ping output
    pkgs.speedtest-cli # internet speed test
    pkgs.urlscan # extract URLs from text blobs
    pkgs.whois # domain info lookup
    pkgs.neg.oryx # TUI traffic sniffer using eBPF (run with sudo; needs BTF kernel)

    # Remote access
    pkgs.abduco # CLI session detach
    pkgs.xxh # SSH wrapper for jumping into remote shells
  ];

}
