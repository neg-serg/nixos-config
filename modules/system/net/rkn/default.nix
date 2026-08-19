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

  # Community-maintained RKN blocklists (family 1andrevich/Re-filter-lists,
  # updated daily; the only live family of clean domain lists — covers
  # youtube/google domains used by zapret2). Researched and rejected:
  # CipherOps/RKN-checker (404), zapret-info dump.csv (IP registry, not
  # domains), itdoginfo/allow-domains (allowlist of opposite semantics),
  # ipsum.lst (IP addresses, for --ipset, not hostlist).
  blocklistUrls = [
    "https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/domains_all.lst" # main list, ~1.3 MB, ~56k domains
    "https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/community.lst" # supplement, 11 KB, clean domains
    "https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/ooni_domains.lst" # supplement, 12.5 KB, domains+IPs (IPs filtered out)
  ];

  rknScript = pkgs.writeShellScript "rkn-domains-fetch" ''
    set -euo pipefail
    BLOCKLIST_DIR="''${BLOCKLIST_DIR:-/var/lib/rkn/domains}"
    mkdir -p "$BLOCKLIST_DIR"

    : > "$BLOCKLIST_DIR/domains_all.tmp"
    for url in ${builtins.concatStringsSep " " blocklistUrls}; do
      ${lib.getExe pkgs.curl} -fsSL --retry 3 --connect-timeout 5 --max-time 30 "$url" \
        | grep -E '^[a-zA-Z0-9][-a-zA-Z0-9]*\.[a-zA-Z]{2,}$' \
        | sort -u >> "$BLOCKLIST_DIR/domains_all.tmp"
    done
    sort -u "$BLOCKLIST_DIR/domains_all.tmp" > "$BLOCKLIST_DIR/domains_all.txt"
    rm -f "$BLOCKLIST_DIR/domains_all.tmp"

    echo "Updated $(wc -l < "$BLOCKLIST_DIR/domains_all.txt") domains"
  '';
in
{
  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.curl ];

    systemd.services.rkn-domains-fetch = {
      description = "RKN domains fetcher";
      # Deliberately NOT a boot dependency: at boot raw.githubusercontent.com
      # is unreachable without zapret2 (chicken-and-egg — this service feeds
      # zapret2 its hostlist), so a boot-time run only burned ~7s of curl
      # retries and failed, blocking multi-user.target. zapret2 starts with
      # the last-known list from StateDirectory; the daily timer and the
      # net-health self-heal refresh it and restart zapret2.
      # curl must resolve raw.githubusercontent.com — wait for network-online
      # (same as zapret2 does) for timer-triggered runs.
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${rknScript}";
        # nfqws reads --hostlist only at start, so restart it to apply the
        # refreshed list. `--no-block` keeps timer-triggered runs from
        # stalling on zapret2's start. `|| true` — zapret2 may be disabled.
        # Needs an explicit shell: ExecStart lines are split on whitespace,
        # no `||`/`--` handling.
        ExecStartPost = "${pkgs.bash}/bin/bash -c 'systemctl restart --no-block zapret2.service || true'";
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
