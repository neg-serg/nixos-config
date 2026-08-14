##
# Module: system/net/net-health
# Purpose: periodic network/DNS/zapret2/firewall health check with
# self-heal for the zapret2 stack and ntfy push notifications.
#
# Architecture:
#   - ntfy-sh server listens on :2586 (all interfaces); topic `net-health`.
#   - systemd timer (every ~5 min) runs the check script:
#       * checks: default route, uplink state, gateway ping, DNS chain
#         (resolved -> unbound -> adguardhome) incl. DNSSEC validation,
#         zapret2 (service, nft rules, real TCP+QUIC bypass), nixos-fw.
#       * self-heal: restarts ONLY the zapret2 stack (service + nft rules
#         via ExecStartPre) and refetches a missing RKN hostlist; network/
#         DNS/firewall failures are only logged and pushed, never restarted.
#       * state transitions (new FAIL / RECOVERED) are logged to journald
#         and pushed to ntfy; a stable state only logs a summary line.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.features.net.netHealth or { };
  # getExe' with explicit program names: iproute2's main binary is `ip`
  # and iputils' is `ping` (getExe would guess iproute2/iputils — broken).
  ip = lib.getExe' pkgs.iproute2 "ip";
  ping = lib.getExe' pkgs.iputils "ping";
  nft = lib.getExe pkgs.nftables;
  curl = lib.getExe pkgs.curl;
  systemctl = "${pkgs.systemd}/bin/systemctl";
  resolvectl = "${pkgs.systemd}/bin/resolvectl";

  zapret2Enabled = config.features.net.zapret2.enable or false;
  rknEnabled = config.features.net.rknDomains.enable or false;
  adguardEnabled = config.services.adguardhome.enable or false;

  # No `set -e`: failing checks are a normal outcome here, only `set -u`.
  netHealthScript = pkgs.writeShellScript "net-health-check" ''
    set -u

    IP="${ip}"
    PING="${ping}"
    NFT="${nft}"
    CURL="${curl}"
    SYSTEMCTL="${systemctl}"
    RESOLVECTL="${resolvectl}"

    STATE=/var/lib/net-health/state
    RESULTS=/var/lib/net-health/results.$$
    NTFY_URL="http://127.0.0.1:2586/net-health"

    # Feature gates substituted at build time from the Nix config.
    ZAPRET2=${lib.boolToString zapret2Enabled}
    RKN=${lib.boolToString rknEnabled}
    ADGUARD=${lib.boolToString adguardEnabled}

    # record a check result: rec <id> <PASS|FAIL>
    rec() {
      echo "$1 $2" >> "$RESULTS"
    }

    # push to ntfy; a failing push is not a failure of the check itself
    push() { # $1 = priority, $2 = message
      $CURL -sS -m 5 -X POST -H "Title: net-health" -H "Priority: $1" -d "$2" "$NTFY_URL" >/dev/null 2>&1 || true
    }

    # zapret2 checks (re-runnable after self-heal)
    zapret2_checks() {
      if $SYSTEMCTL is-active --quiet zapret2; then
        rec zapret2-active PASS
      else
        rec zapret2-active FAIL
      fi
      if $NFT list table inet zapret2 2>/dev/null | grep -q queue; then
        rec zapret2-nft PASS
      else
        rec zapret2-nft FAIL
      fi
      if [ "$($CURL -4 -sS -o /dev/null -w '%{http_code}' --max-time 10 https://www.youtube.com/)" = "200" ]; then
        rec zapret2-tcp PASS
      else
        rec zapret2-tcp FAIL
      fi
      if [ "$($CURL --http3 -sS -o /dev/null -w '%{http_code}' --max-time 10 https://www.youtube.com/)" = "200" ]; then
        rec zapret2-quic PASS
      else
        rec zapret2-quic FAIL
      fi
    }

    : > "$RESULTS"

    # --- checks ---
    if $IP route show default | grep -q .; then rec route-default PASS; else rec route-default FAIL; fi
    if dev=$($IP route show default | awk 'NR==1{print $5}'); [ -n "$dev" ] && $IP link show "$dev" | grep -q "state UP"; then rec uplink-up PASS; else rec uplink-up FAIL; fi
    if gw=$($IP route show default | awk 'NR==1{print $3}'); [ -n "$gw" ] && $PING -c1 -W2 -q "$gw" >/dev/null 2>&1; then rec gateway-ping PASS; else rec gateway-ping FAIL; fi
    if $SYSTEMCTL is-active --quiet systemd-resolved; then rec dns-resolved PASS; else rec dns-resolved FAIL; fi
    if $SYSTEMCTL is-active --quiet unbound; then rec dns-unbound PASS; else rec dns-unbound FAIL; fi
    if [ "$ADGUARD" = "true" ]; then
      if $SYSTEMCTL is-active --quiet adguardhome; then rec dns-adguardhome PASS; else rec dns-adguardhome FAIL; fi
    fi
    if getent ahostsv4 example.com | grep -q .; then rec dns-resolve PASS; else rec dns-resolve FAIL; fi
    if $RESOLVECTL query cloudflare.com >/dev/null 2>&1 && ! $RESOLVECTL query dnssec-failed.org >/dev/null 2>&1; then rec dns-dnssec PASS; else rec dns-dnssec FAIL; fi
    if [ "$ZAPRET2" = "true" ]; then
      zapret2_checks
    fi
    if $NFT list chain ip filter INPUT 2>/dev/null | grep -q nixos-fw; then rec fw-input PASS; else rec fw-input FAIL; fi

    # --- self-heal: zapret2 stack only ---
    # Restart re-runs ExecStartPre (preflight + nft table reset + nft -f),
    # so it fixes both the service and the nft rules.
    if [ "$ZAPRET2" = "true" ] && grep -q 'zapret2-active FAIL\|zapret2-nft FAIL' "$RESULTS"; then
      echo "[net-health] self-heal: restarting zapret2"
      $SYSTEMCTL restart zapret2
      sleep 2
      # replace the previous zapret2 results with a fresh run
      grep -v '^zapret2-' "$RESULTS" > "$RESULTS.tmp"
      mv "$RESULTS.tmp" "$RESULTS"
      zapret2_checks
    fi

    # rkn hostlist missing/empty -> refetch (applied to zapret2 on its restart)
    if [ "$RKN" = "true" ] && [ ! -s /var/lib/rkn/domains/domains_all.txt ]; then
      echo "[net-health] self-heal: rkn hostlist missing, refetching"
      $SYSTEMCTL start rkn-domains-fetch
      sleep 1
    fi

    # --- state diff: journald + ntfy push only on transitions ---
    failing_old=""
    if [ -f "$STATE" ]; then
      failing_old=$(cat "$STATE")
    fi
    failing_new=$(grep ' FAIL$' "$RESULTS" | sed 's/ FAIL$//')

    # new failures -> FAIL push
    if [ -n "$failing_new" ]; then
      printf '%s\n' "$failing_new" | while IFS= read -r id; do
        if ! printf '%s\n' "$failing_old" | grep -Fqx "$id"; then
          msg="[net-health] FAIL $id"
          echo "$msg"
          push high "$msg"
        fi
      done
    fi

    # cleared failures -> RECOVERED push
    if [ -n "$failing_old" ]; then
      printf '%s\n' "$failing_old" | while IFS= read -r id; do
        if ! printf '%s\n' "$failing_new" | grep -Fqx "$id"; then
          msg="[net-health] RECOVERED $id"
          echo "$msg"
          push default "$msg"
        fi
      done
    fi

    # persist the new failing set
    printf '%s\n' "$failing_new" > "$STATE"

    ok=$(grep -c ' PASS$' "$RESULTS")
    bad=$(grep -c ' FAIL$' "$RESULTS")
    echo "[net-health] summary: $ok ok, $bad fail"

    rm -f "$RESULTS"
  '';
in
{
  config = mkIf cfg.enable {
    # Self-hosted ntfy server: LAN subscribers (e.g. phone) read topic
    # `net-health` at http://<odin-LAN-ip>:2586/net-health. No auth (LAN
    # only).
    services.ntfy-sh = {
      enable = true;
      settings = {
        # all interfaces; the module default is 127.0.0.1:2586
        listen-http = ":2586";
        # nixpkgs 26.05 ntfy-sh module requires base-url (YAML generation
        # forces every declared option). It is only used for attachments/
        # e-mail/iOS, none of which we use — LAN polling hits the IP
        # directly, so a localhost placeholder avoids hardcoding a
        # DHCP-dependent address.
        base-url = "http://127.0.0.1:2586";
      };
    };

    networking.firewall.interfaces = {
      net0.allowedTCPPorts = [ 2586 ]; # ntfy server (MikroTik LAN 10.0.2.140/27)
      net1.allowedTCPPorts = [ 2586 ]; # ntfy server (uplink, router 192.168.2.x)
      br0.allowedTCPPorts = [ 2586 ]; # ntfy server (libvirt bridge)
    };

    systemd.services.net-health = {
      description = "Network/DNS/zapret2 health check and self-heal";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      # Script uses awk/getent bare; the default unit PATH only has
      # coreutils/grep/sed/systemd, so add gawk and glibc's getent output.
      # NB: `path` is a top-level unit option (rendered as Environment=PATH),
      # NOT a serviceConfig key — inside serviceConfig it would be emitted
      # as a raw `path=` directive that systemd ignores.
      path = [
        pkgs.gawk # awk used by the check script (route parsing)
        pkgs.glibc.getent # getent for DNS resolution check (separate glibc output)
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${netHealthScript}";
        StateDirectory = "net-health";
      };
    };

    systemd.timers.net-health = {
      description = "Periodic network health check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2m";
        OnUnitActiveSec = "5m";
        Persistent = true;
        AccuracySec = "1m";
      };
    };
  };
}
