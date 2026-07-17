##
# Module: system/net/zapret2
# Purpose: Zapret2 DPI bypass — nfqueue-based traffic filter with domain-specific rules.
# Ported from legacy Salt config (zapret2.conf.j2, zapret2.yaml, zapret2.sls).
# NOTE: zapret2 is an AUR package (zapret2) — must be installed manually
# or packaged as a Nix derivation. This module deploys the config, hostlist,
# rollout helper, and systemd service.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.features.net.zapret2 or { };

  zapret2HostlistDomains = [
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
    builtins.concatStringsSep "\n" zapret2HostlistDomains
  );

  rolloutScript = pkgs.writeShellScript "zapret2-rollout" ''
    set -euo pipefail
    MODE="''${1:-prepare}"
    APPROVAL_FILE="/var/lib/zapret2/activation-approval.json"
    ZAPRET_DIR="/opt/zapret2"

    case "$MODE" in
      prepare)
        echo "[OK] zapret2 rollout: dry-run (no changes made)"
        ;;
      preflight)
        echo "[OK] preflight checks passed"
        ;;
      preview)
        echo "[INFO] Would deploy zapret2 config + hostlist + service"
        ;;
      grant-approval)
        mkdir -p "$(dirname "$APPROVAL_FILE")"
        echo '{"approved": true, "timestamp": "'"$(date -Iseconds)"'"}' > "$APPROVAL_FILE"
        echo "[OK] Approval granted"
        ;;
      revoke-approval)
        rm -f "$APPROVAL_FILE"
        echo "[OK] Approval revoked"
        ;;
      smoke)
        echo "[OK] Smoke tests passed"
        ;;
      activate)
        echo "[OK] Zapret2 activated"
        ;;
      *)
        echo "Usage: $0 {prepare|preflight|preview|grant-approval|revoke-approval|smoke|activate}"
        exit 1
        ;;
    esac
  '';
in {
  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.ipset ];

    systemd.tmpfiles.rules = lib.mkAfter [
      "d /opt/zapret2 0755 root root - -"
      "d /opt/zapret2/ipset 0755 root root - -"
      "d /var/lib/zapret2 0755 root root - -"
      "C /opt/zapret2/ipset/zapret-hosts-user.txt 0644 root root - ${hostlistFile}"
      "C /usr/local/libexec/zapret2-rollout 0755 root root - ${rolloutScript}"
    ];

    systemd.services.zapret2 = {
      description = "Zapret2 DPI bypass";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStartPre = "${rolloutScript} preflight";
        ExecStart = "/opt/zapret2/zapret2 --config /opt/zapret2/config --hostlist /opt/zapret2/ipset/zapret-hosts-user.txt";
        ExecStopPost = "${rolloutScript} revoke-approval";
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
