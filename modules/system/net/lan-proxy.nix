{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.net.lan-proxy;

  sockd-start = pkgs.writeShellScript "lan-proxy-start" ''
    EXT_IFACE=$(${pkgs.iproute2}/bin/ip -4 route show default | ${pkgs.gawk}/bin/awk '{print $5; exit}')
    CONFIG=$(${pkgs.coreutils}/bin/mktemp)
    trap 'rm -f "$CONFIG"' EXIT
    cat > "$CONFIG" <<EOF
internal: 0.0.0.0 port = 10809
external: $EXT_IFACE
socksmethod: none
clientmethod: none
client pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  log: error
}
socks pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  log: error
}
EOF
    exec ${pkgs.dante}/bin/sockd -f "$CONFIG"
  '';
in
lib.mkIf cfg.enable {
  environment.systemPackages = [
    pkgs.dante # SOCKS5 proxy server (sockd)
  ];

  networking.firewall.allowedTCPPorts = [ 10809 ];

  systemd.services.lan-proxy = {
    description = "LAN SOCKS5 proxy – no auth (0.0.0.0:10809)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "simple";
      User = "nobody";
      ExecStart = sockd-start;
      Restart = "on-failure";
    };
  };
}
