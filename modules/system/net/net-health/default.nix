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

  zapret2Enabled = config.lib.neg.enabled "net.zapret2";
  rknEnabled = config.lib.neg.enabled "net.rknDomains";
  adguardEnabled = config.services.adguardhome.enable or false;

  # No `set -e`: failing checks are a normal outcome here, only `set -u`.
  netHealthScript = pkgs.writeShellScript "net-health-check" (
    builtins.readFile (
      pkgs.replaceVars ./check.sh {
        inherit
          ip
          ping
          nft
          curl
          systemctl
          resolvectl
          ;
        zapret2Enabled = lib.boolToString zapret2Enabled;
        rknEnabled = lib.boolToString rknEnabled;
        adguardEnabled = lib.boolToString adguardEnabled;
      }
    )
  );
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
