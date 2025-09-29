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
    pkgs.impala # tui for wifi management
    pkgs.iwd # install iwd without enabling the service
    pkgs.bandwhich # display network utilization per process
    pkgs.cacert # for curl certificate verification
    pkgs.curlie # feature-rich httpie
    pkgs.dnsutils # dns command-line tools (dig, nslookup)
    pkgs.dogdns # commandline dns client
    pkgs.ethtool # control eth hardware and drivers
    pkgs.fping # like ping -c1
    pkgs.geoip # geoip lookup
    pkgs.httpie # fancy curl
    pkgs.httpstat # fancy curl -v
    pkgs.iftop # display bandwidth
    pkgs.inetutils # common network programs
    pkgs.ipcalc # calculate ip addr stuff
    pkgs.iputils # set of small useful utilities for Linux networking
    # pkgs.magic-wormhole # secure transfer between computers
    pkgs.netcat-openbsd # openbsd netcat variant
    pkgs.netdiscover # another network scan
    pkgs.nmap # port scanner
    pkgs.rustscan # fast port scanner companion to nmap
    pkgs.zmap # internet-scale network scanner
    pkgs.masscan # asynchronous port scanner like nmap
    pkgs.rclone # rsync for cloud storage
    pkgs.socat # multipurpose relay
    pkgs.sshfs # ssh mount
    pkgs.tcpdump # best friend to show network stuff
    pkgs.tcptraceroute # traceroute without icmp
    pkgs.traceroute # basic traceroute
    pkgs.trippy # net analysis tool like ping + traceroute
    pkgs.w3m # cli browser
    pkgs.xh # friendly and fast tool to send http requests

    pkgs.axel # console downloading program
    pkgs.curl # transfer curl
    pkgs.wget2 # non-interactive downloader

    pkgs.aircrack-ng # stuff for wifi security
    pkgs.hcxdumptool # wpa scanner
    pkgs.netscanner # alternative traffic viewer
    pkgs.netsniff-ng # sniffer
    pkgs.termshark # more modern tshark interface inspired by wireshark
    pkgs.tshark # sniffer tui
    pkgs.wireshark # sniffer gui
  ];

  # Expose iwd's systemd unit so it can be started manually when required
  systemd.packages = [pkgs.iwd];

  # Provide D-Bus service definition for manual activation of iwd
  services.dbus.packages = [pkgs.iwd];
}
