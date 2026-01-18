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
}:
let
  wifiEnabled = config.profiles.network.wifi.enable || (config.features.net.wifi.enable or false);
in
{
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
    pkgs.bandwhich # Display network utilization per process in real-time
    pkgs.iftop # Display bandwidth usage on an interface

    # -- DNS --
    pkgs.dnsutils # dns command-line tools (dig, nslookup)
    pkgs.dogdns # commandline dns client

    # -- Download --
    pkgs.axel # Multi-threaded download accelerator
    pkgs.curl # Command line tool for transferring data with URLs
    pkgs.wget2 # Wget successor with multi-threading and HTTP/2 support

    # -- HTTP --
    pkgs.cacert # Bundle of CA certificates for SSL/TLS verification
    pkgs.curlie # curl wrapper that adds HTTPie-like features
    pkgs.httpie # Modern, user-friendly command-line HTTP client
    pkgs.httpstat # curl statistics visualizer
    pkgs.xh # Friendly and fast tool to send HTTP requests

    # -- IP / Routing --
    pkgs.fping # Fast ping
    pkgs.geoip # IP-to-location lookup utility
    pkgs.ipcalc # IPv4/IPv6 address calculator
    pkgs.tcptraceroute # Traceroute implementation using TCP packets
    pkgs.traceroute # Print the route packets trace to network host

    # -- Remote / Transfer --
    pkgs.socat # Multipurpose relay (bidirectional data transfer)
    pkgs.sshfs # Mount remote directories over SSH

    # -- Utilities --
    pkgs.ethtool # Query and control network device settings
    pkgs.inetutils # Collection of common network programs
    pkgs.iputils # Networking utilities (ping, arping, etc.)
    pkgs.netcat-openbsd # TCP/IP swiss army knife (OpenBSD variant)
    pkgs.w3m # Text-mode web browser and pager
  ]
  ++ (lib.optionals wifiEnabled [
    # -- WiFi --
    pkgs.iwd # install iwd without enabling the service
  ]);

  # Expose iwd's systemd unit so it can be started manually when required
  systemd.packages = lib.optionals wifiEnabled [ pkgs.iwd ]; # Wireless daemon for Linux
  # Provide D-Bus service definition for manual activation of iwd
  services.dbus.packages = lib.optionals wifiEnabled [ pkgs.iwd ]; # Wireless daemon for Linux
}
