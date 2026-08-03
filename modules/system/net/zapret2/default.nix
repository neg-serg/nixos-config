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

  # nfqws strategy flags (verified against nfqws -h)
  strategyFlags = [
    "--qnum=1"
    "--filter-tcp=80,443"
    "--dpi-desync=fake"
    "--dpi-desync-fooling=md5sig"
    "--hostlist=/etc/zapret2/zapret-hosts-user.txt"
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
    environment.systemPackages = [ zapret2 ];

    systemd.tmpfiles.rules = lib.mkAfter [
      "d /etc/zapret2 0755 root root - -"
      "C /etc/zapret2/zapret-hosts-user.txt 0644 root root - ${hostlistFile}"
      "C /usr/local/libexec/zapret2-rollout 0755 root root - ${rolloutScript}"
    ];

    systemd.services.zapret2 = {
      description = "Zapret2 DPI bypass (nfqws)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStartPre = "${rolloutScript} preflight";
        ExecStart = "${nfqws} ${builtins.concatStringsSep " " strategyFlags}";
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
