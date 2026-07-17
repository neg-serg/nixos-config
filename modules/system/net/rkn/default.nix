##
# Module: system/net/rkn
# Purpose: RKN (Russian internet regulator) blocked domains integration.
# Fetches domain blocklists, feeds to sing-box and VPN split router.
# Ported from legacy Salt config (rkn-domains-integration.sh).
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.features.net.rknDomains or { };

  rknScript = pkgs.writeShellScript "rkn-domains-fetch" ''
    set -euo pipefail
    BLOCKLIST_DIR="''${BLOCKLIST_DIR:-/var/lib/rkn/domains}"
    mkdir -p "$BLOCKLIST_DIR"

    # Fetch blocklists from known GitHub sources (community-maintained)
    SOURCES=(
      "https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/domains_all.lst"
      "https://raw.githubusercontent.com/CipherOps/RKN-checker/main/rkn-domains.txt"
    )

    for url in "''${SOURCES[@]}"; do
      name=$(basename "$url" | sed 's/\.lst$//;s/\.txt$//')
      ${lib.getExe pkgs.curl} -fsSL --retry 3 --max-time 60 "$url" \
        | grep -E '^[a-zA-Z0-9][-a-zA-Z0-9]*\.[a-zA-Z]{2,}$' \
        | sort -u > "$BLOCKLIST_DIR/$name.txt"
    done

    # Merge all lists
    cat "$BLOCKLIST_DIR"/*.txt | sort -u > "$BLOCKLIST_DIR/domains_all.txt"
    echo "Updated $(wc -l < "$BLOCKLIST_DIR/domains_all.txt") domains"
  '';
in {
  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.curl ];

    systemd.services.rkn-domains-fetch = {
      description = "RKN domains fetcher";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${rknScript}";
        StateDirectory = "rkn/domains";
        Environment = "BLOCKLIST_DIR=/var/lib/rkn/domains";
      };
    };

    systemd.timers.rkn-domains-fetch = {
      description = "Daily RKN domain fetch";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
  };
}
