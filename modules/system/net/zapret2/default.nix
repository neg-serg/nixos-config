##
# Module: system/net/zapret2
# Purpose: Zapret2 DPI bypass — nfqueue-based traffic filter with domain hostlists.
#
# Architecture (matches upstream bol-van/zapret, verified against nfqws -h):
#   nfqws --filter-tcp=... --hostlist=<file> ... @<config>
#   - config file passed via `@file` (must be the only argument → we pass
#     strategy flags directly in ExecStart and hostlist via --hostlist)
#   - hostlist is a native nfqws flag (one host per line, subdomains auto-apply)
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.features.net.zapret2 or { };

  zapret2 = pkgs.zapret2;
  nfqws = "${zapret2}/bin/nfqws";

  # Use the runtime RKN blocklist when enabled (fresh, ~56k domains incl.
  # youtube/google), else the static hostlist below.
  rknHostlist = "/var/lib/rkn/domains/domains_all.txt";
  hostlistArg =
    if (config.lib.neg.enabled "net.rknDomains") then
      "--hostlist=${rknHostlist}"
    else
      "--hostlist=/etc/zapret2/zapret-hosts-user.txt";
  # Domain hostlists for desync (upstream default + user additions)
  hostlistDomains = [
    "youtube.com"
    "www.youtube.com"
    "m.youtube.com"
    "music.youtube.com"
    "youtu.be"
    "youtubei.googleapis.com"
    "ytimg.com"
    "i.ytimg.com"
    "googlevideo.com"
    "youtube-nocookie.com"
    "yt3.ggpht.com"
    "lh3.googleusercontent.com"
    "registry.ollama.ai"
  ];

  hostlistFile = pkgs.writeText "zapret-hosts-user.txt" (
    builtins.concatStringsSep "\n" hostlistDomains
  );

  # Redirect matching traffic to NFQUEUE queue 1 (nfqws --qnum=1).
  # Without a queue rule, nfqws fails with nfq_unbind_pf(): Invalid argument.
  nftablesRules = pkgs.writeText "zapret2-nftables.conf" ''
    table inet zapret2 {
      # Outbound (client->server) direction — nfqws must see the TLS
      # ClientHello / HTTP request to desync it. postrouting (not output)
      # so nfqws can resolve the egress interface for generated packets.
      chain postrouting {
        type filter hook postrouting priority mangle; policy accept;
        # Skip local/LAN/loopback destinations — don't touch local HTTP(S).
        ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8 } return
        # Exclude nfqws-generated packets (fwmark 0x40000000) to avoid loops.
        meta mark and 0x40000000 == 0 tcp dport { 80, 443 } queue num 1 bypass
        meta mark and 0x40000000 == 0 udp dport 443 queue num 1 bypass
      }
      # Inbound (server->client) replies for response-side desync.
      chain prerouting {
        type filter hook prerouting priority filter; policy accept;
        # Skip local/LAN/loopback destinations — don't touch local HTTP(S).
        ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8 } return
        meta mark and 0x40000000 == 0 tcp sport { 80, 443 } queue num 1 bypass
      }
    }
  '';

  # Multi-strategy (nfqws applies the first strategy whose port filter
  # matches; common flags --qnum/hostlist must precede the first --new):
  #   TCP-TLS:  --filter-tcp=443 hostfakesplit/md5sig
  #   --new     TCP-HTTP: --filter-tcp=80 hostfakesplit/md5sig
  #   --new     UDP-QUIC: --filter-udp=443 fake/badsum
  # hostfakesplit verified live against the provider DPI: plain fake is
  # detected (the fake ClientHello still carries the real SNI), split
  # modes hide the hostname from DPI reassembly.
  # Auto modes: --dpi-desync-autottl (adaptive fake-packet TTL),
  # --bind-fix4 (correct egress iface for generated packets),
  # --hostlist-auto (nfqws appends domains on repeated failures).
  strategyFlags = [
    "--qnum=1"
    hostlistArg
    "--filter-tcp=443"
    "--dpi-desync=hostfakesplit"
    "--dpi-desync-fooling=md5sig"
    "--new"
    "--filter-tcp=80"
    "--dpi-desync=hostfakesplit"
    "--dpi-desync-fooling=md5sig"
    "--new"
    "--filter-udp=443"
    "--dpi-desync=fake"
    "--dpi-desync-fooling=badsum"
    "--dpi-desync-autottl"
    "--bind-fix4"
    "--hostlist-auto=/var/lib/zapret2/hostlist-auto.txt"
  ];

  rolloutScript = pkgs.writeShellScript "zapret2-rollout" ''
    set -euo pipefail
    MODE="''${1:-prepare}"
    BIN="${nfqws}"

    case "$MODE" in
      prepare|preflight)
        [ -x "$BIN" ] || { echo "ERROR: nfqws not found at $BIN" >&2; exit 1; }
        "$BIN" --dry-run ${builtins.concatStringsSep " " strategyFlags} >/dev/null 2>&1 \
          || { echo "ERROR: nfqws --dry-run failed" >&2; exit 1; }
        echo "[OK] nfqws present and config valid"
        ;;
      preview)
        echo "[INFO] zapret2: ${nfqws}"
        echo "       flags: ${builtins.concatStringsSep " " strategyFlags}"
        ;;
      smoke)
        "$BIN" --version
        ;;
      activate)
        systemctl start zapret2
        echo "[OK] zapret2 activated"
        ;;
      deactivate)
        systemctl stop zapret2
        echo "[OK] zapret2 deactivated"
        ;;
      *)
        echo "Usage: $0 {prepare|preflight|preview|smoke|activate|deactivate}"
        exit 1
        ;;
    esac
  '';
in
{
  config = mkIf cfg.enable {
    # nfqws requires nfqueue in-kernel: CONFIG_NETFILTER_NETLINK_QUEUE,
    # CONFIG_NFNETLINK_QUEUE, CONFIG_NFT_QUEUE. Apply as kernel patch.
    boot.kernelPatches = [
      {
        name = "zapret2-nfqueue";
        patch = null;
        structuredExtraConfig = with lib.kernel; {
          NETFILTER_NETLINK_QUEUE = yes;
          NFNETLINK_QUEUE = module;
          NFT_QUEUE = module;
        };
      }
    ];

    environment.systemPackages = [ zapret2 ];

    systemd.tmpfiles.rules = lib.mkAfter [
      "d /etc/zapret2 0755 root root - -"
      "C /etc/zapret2/zapret-hosts-user.txt 0644 root root - ${hostlistFile}"
      "C /usr/local/libexec/zapret2-rollout 0755 root root - ${rolloutScript}"
    ];

    systemd.services.zapret2 = {
      description = "Zapret2 DPI bypass (nfqws)";
      after = [
        "network-online.target"
      ]
      ++ lib.optionals (config.lib.neg.enabled "net.rknDomains") [ "rkn-domains-fetch.service" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.nftables ];
      serviceConfig = {
        Type = "simple";
        ExecStartPre = [
          "${rolloutScript} preflight"
          # nft -f appends to existing chains; drop the table first so
          # restarting the service cannot accumulate duplicate rules.
          "${pkgs.bash}/bin/bash -c '${pkgs.nftables}/bin/nft delete table inet zapret2 2>/dev/null || true'"
          "${pkgs.nftables}/bin/nft -f ${nftablesRules}"
        ];
        ExecStart = "${nfqws} ${builtins.concatStringsSep " " strategyFlags}";
        Restart = "on-failure";
        RestartSec = 10;
        StateDirectory = "zapret2";
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        AmbientCapabilities = "CAP_NET_ADMIN CAP_NET_RAW";
        CapabilityBoundingSet = "CAP_NET_ADMIN CAP_NET_RAW";
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
}
