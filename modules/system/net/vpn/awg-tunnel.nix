##
# Module: system/net/vpn/awg-tunnel
# Purpose: AmneziaWG obfuscated WireGuard tunnel.
# Ported from legacy Salt config (awg_tunnel.yaml, awg-tunnel.conf.j2).
# NOTE: Requires amneziawg-dkms kernel module and amneziawg-tools (AUR-only).
# Install manually or package as a Nix derivation.
# Secrets (private_key, preshared_key) should come from SOPS age keys.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.features.net.awgTunnel or { };
in {
  config = mkIf cfg.enable {
    environment.etc."wireguard/awg-tunnel.conf" = {
      mode = "0600";
      user = "root";
      group = "systemd-network";
      text = ''
        [Interface]
        Address = 10.8.1.2/32
        DNS = 1.1.1.1, 1.0.0.1
        MTU = 1420
        Jc = 4
        Jmin = 10
        Jmax = 50
        S1 = 76
        S2 = 115
        S3 = 33
        S4 = 17
        H1 = 1893919229-1995198969
        H2 = 2103365535-2146601695
        H3 = 2147101763-2147234958
        H4 = 2147289098-2147350702
        I1 = <b 0x084481800001000300000000077469636b65747306776964676574096b696e6f706f69736b0272750000010001c00c0005000100000039001806776964676574077469636b6574730679616e646578c025c0390005000100000039002b1765787465726e616c2d7469636b6574732d776964676574066166697368610679616e646578036e657400c05d000100010000001c000457fafe25>

        [Peer]
        PublicKey = rvfWeKZN3j/MoUpjbOyqK3zYH7Zj1yYeME0Djj+iwjc=
        AllowedIPs = 0.0.0.0/0, ::/0
        Endpoint = 104.223.120.154:45735
        PersistentKeepalive = 25
      '';
    };

    systemd.services.awg-tunnel = {
      description = "AmneziaWG obfuscated tunnel";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.wireguard-tools ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${lib.getExe' pkgs.wireguard-tools "wg-quick"} up awg-tunnel";
        ExecStop = "${lib.getExe' pkgs.wireguard-tools "wg-quick"} down awg-tunnel";
        Restart = "on-failure";
        RestartSec = 10;
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
}
