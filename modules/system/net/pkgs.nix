##
# Module: system/net/pkgs
# Purpose: Networking tools; firewall ranges for KDE Connect when enabled.
# Key options: uses config.programs.kdeconnect.enable
# Dependencies: pkgs; firewall.
{
  lib,
  config,
  pkgs,
  ...
}: {
  # Open KDE Connect ports only if the program is enabled
  networking.firewall = lib.mkIf (config.programs.kdeconnect.enable or false) {
    allowedTCPPortRanges = [
      {
        from = 1714;
        to = 1764;
      }
    ];
    allowedUDPPortRanges = [
      {
        from = 1714;
        to = 1764;
      }
    ];
  };

  environment.systemPackages = [
    # -- Analysis / Traffic --
    pkgs.bandwhich # display network utilization per process
    pkgs.iftop # display bandwidth
    pkgs.netsniff-ng # sniffer
    pkgs.tcpdump # best friend to show network stuff
    pkgs.termshark # more modern tshark interface inspired by wireshark
    pkgs.trippy # net analysis tool like ping + traceroute
    pkgs.tshark # sniffer tui
    pkgs.wireshark # sniffer gui

    # -- DNS --
    pkgs.dnsutils # dns command-line tools (dig, nslookup)
    pkgs.dogdns # commandline dns client

    # -- Download --
    pkgs.axel # console downloading program
    pkgs.curl # transfer curl
    pkgs.wget2 # non-interactive downloader

    # -- HTTP --
    pkgs.cacert # for curl certificate verification
    pkgs.curlie # feature-rich httpie
    pkgs.httpie # fancy curl
    pkgs.httpstat # fancy curl -v
    pkgs.xh # friendly and fast tool to send http requests

    # -- IP / Routing --
    pkgs.fping # like ping -c1
    pkgs.geoip # geoip lookup
    pkgs.ipcalc # calculate ip addr stuff
    pkgs.tcptraceroute # traceroute without icmp
    pkgs.traceroute # basic traceroute

    # -- Network Scanning --
    pkgs.masscan # asynchronous port scanner like nmap
    pkgs.netdiscover # another network scan
    pkgs.netscanner # alternative traffic viewer
    pkgs.nmap # port scanner
    pkgs.rustscan # fast port scanner companion to nmap
    pkgs.zmap # internet-scale network scanner

    # -- Remote / Transfer --
    pkgs.rclone # rsync for cloud storage
    pkgs.socat # multipurpose relay
    pkgs.sshfs # ssh mount

    # -- Utilities --
    pkgs.ethtool # control eth hardware and drivers
    pkgs.inetutils # common network programs
    pkgs.iputils # set of small useful utilities for Linux networking
    pkgs.netcat-openbsd # openbsd netcat variant
    pkgs.w3m # cli browser

    # -- WiFi --
    pkgs.aircrack-ng # stuff for wifi security
    pkgs.hcxdumptool # wpa scanner
    pkgs.impala # tui for wifi management
    pkgs.iwd # install iwd without enabling the service
  ];

  # Expose iwd's systemd unit so it can be started manually when required
  systemd.packages = [pkgs.iwd];

  # Provide D-Bus service definition for manual activation of iwd
  services.dbus.packages = [pkgs.iwd];
}
