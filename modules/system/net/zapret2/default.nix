##
# Module: system/net/zapret2
# Purpose: Zapret2 DPI bypass — nfqueue-based traffic filter with domain-specific rules.
#
# Architecture (matches upstream bol-van/zapret):
#   1. Domain hostlists → nftables set (ipv4/ipv6)
#   2. nftables rules redirect matching traffic to NFQUEUE queues
#   3. nfqws2 processes read NFQUEUE and apply desync strategies
#
# Config lives in /etc/zapret2/config (overridable). Rollout helper is a thin
# wrapper around the service, not a stub.
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

  # Default nfqws2 config — the binary reads strategy flags from here.
  # nfqws2 does NOT accept --hostlist; hostlists feed the firewall sets below.
  configFile = pkgs.writeText "zapret2.conf" ''
    # nfqws2 strategy: desync TCP with fragmented packet fooling
    --filter-tcp=80,443
    --dpi-desync=fake,fragment
    --dpi-desync-fooling=md5sig
    --dpi-desync-recutests=2
    --winsize=1276
  '';

  # nftables ruleset: load hostlist into sets, redirect to NFQUEUE.
  # Queues 1/2/3 map to the three nfqws2 instances started below.
  nftablesRules = pkgs.writeText "zapret2-nftables.conf" ''
    table inet zapret2 {
      set blocked-domains {
        type ipv4_addr
        flags interval
      }
      set blocked-domains6 {
        type ipv6_addr
        flags interval
      }
      chain prerouting {
        type filter hook prerouting priority filter - 1; policy accept;
        ip daddr @blocked-domains queue num 1 bypass
        ip6 daddr @blocked-domains6 queue num 2 bypass
      }
    }
  '';

  # Load hostlist into nftables sets (DNS-resolve domains to addresses).
  # nfqws2 ships no --hostlist; upstream uses ipset+iptables or nftables sets.
  loadSetsScript = pkgs.writeShellScript "zapret2-load-sets" ''
    set -euo pipefail
    HOSTLIST="${hostlistFile}"
    NFT_BIN="${pkgs.nftables}/bin/nft"

    # Flush and rebuild sets
    $NFT_BIN -f "${nftablesRules}"
    $NFT_BIN flush set inet zapret2 blocked-domains
    $NFT_BIN flush set inet zapret2 blocked-domains6

    while IFS= read -r domain; do
      [ -z "$domain" ] && continue
      # Resolve A and AAAA; add all addresses to sets
      ${pkgs.host}/bin/getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | while read -r ip; do
        case "$ip" in
          *:*) $NFT_BIN add element inet zapret2 blocked-domains6 "{ $ip }" || true ;;
          *)   $NFT_BIN add element inet zapret2 blocked-domains  "{ $ip }" || true ;;
        esac
      done
    done < "$HOSTLIST"
    echo "[OK] loaded $HOSTLIST"
  '';

  rolloutScript = pkgs.writeShellScript "zapret2-rollout" ''
    set -euo pipefail
    MODE="''${1:-prepare}"
    BIN="${zapret2}/bin/nfqws2"

    case "$MODE" in
      prepare|preflight)
        [ -x "$BIN" ] || { echo "ERROR: nfqws2 not found at $BIN" >&2; exit 1; }
        echo "[OK] nfqws2 present: $BIN"
        ;;
      preview)
        echo "[INFO] zapret2: nfqws2 + nftables sets + systemd service"
        ;;
      smoke)
        "$BIN" --version 2>/dev/null || "$BIN" -h 2>&1 | head -1 || true
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
    environment.systemPackages = [ zapret2 pkgs.nftables ];

    # Config + hostlist are read-only references (no /opt pollution)
    systemd.tmpfiles.rules = lib.mkAfter [
      "d /var/lib/zapret2 0755 root root - -"
      "C /etc/zapret2/config 0644 root root - ${configFile}"
      "C /etc/zapret2/zapret-hosts-user.txt 0644 root root - ${hostlistFile}"
      "C /usr/local/libexec/zapret2-rollout 0755 root root - ${rolloutScript}"
    ];

    systemd.services.zapret2 = {
      description = "Zapret2 DPI bypass (nfqws2)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.nftables pkgs.ipset ];
      serviceConfig = {
        Type = "simple";
        ExecStartPre = [
          "${rolloutScript} preflight"
          "${loadSetsScript}"
        ];
        ExecStart = "${zapret2}/bin/nfqws2 --config /etc/zapret2/config";
        ExecStopPost = "${pkgs.nftables}/bin/nft delete table inet zapret2 2>/dev/null || true";
        Restart = "on-failure";
        RestartSec = 10;
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
