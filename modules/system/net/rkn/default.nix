##
# Module: system/net/rkn
# Purpose: RKN (Russian internet regulator) blocked domains integration.
# Fetches the community-maintained domain blocklist and feeds it to zapret2
# as its --hostlist, so DPI bypass is applied to blocked domains only.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.features.net.rknDomains or { };

  # Community-maintained RKN blocklist. Former second source
  # (CipherOps/RKN-checker, zapret-info dump.csv) is dead — this one is
  # updated daily and covers youtube/google domains used by zapret2.
  blocklistUrl = "https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/domains_all.lst";

  rknScript = pkgs.writeShellScript "rkn-domains-fetch" ''
    set -euo pipefail
    BLOCKLIST_DIR="''${BLOCKLIST_DIR:-/var/lib/rkn/domains}"
    mkdir -p "$BLOCKLIST_DIR"

    ${lib.getExe pkgs.curl} -fsSL --retry 3 --max-time 120 "${blocklistUrl}" \
      | grep -E '^[a-zA-Z0-9][-a-zA-Z0-9]*\.[a-zA-Z]{2,}$' \
      | sort -u > "$BLOCKLIST_DIR/domains_all.txt"

    echo "Updated $(wc -l < "$BLOCKLIST_DIR/domains_all.txt") domains"
  '';
in
{
  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.curl ];

    systemd.services.rkn-domains-fetch = {
      description = "RKN domains fetcher";
      # Run at boot so zapret2 (also wanted by multi-user.target) starts
      # with a fresh list; Before is a no-op when zapret2 is not enabled.
      wantedBy = [ "multi-user.target" ];
      before = [ "zapret2.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${rknScript}";
        # nfqws reads --hostlist only at start, so restart it to apply
        # the refreshed list. `|| true` — zapret2 may be disabled.
        ExecStartPost = "${pkgs.systemd}/bin/systemctl restart zapret2.service || true";
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
