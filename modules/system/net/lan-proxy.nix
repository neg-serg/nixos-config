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
    exec ${pkgs.dante}/bin/sockd -f <(
      printf 'internal: 0.0.0.0 port = 10809\n'
      printf 'external: %s\n' "$EXT_IFACE"
      printf 'socksmethod: none\n'
      printf 'clientmethod: none\n'
      printf 'client pass {\n'
      printf '  from: 0.0.0.0/0 to: 0.0.0.0/0\n'
      printf '  log: error\n'
      printf '}\n'
      printf 'socks pass {\n'
      printf '  from: 0.0.0.0/0 to: 0.0.0.0/0\n'
      printf '  log: error\n'
      printf '}\n'
    )
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
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "simple";
      User = "nobody";
      ExecStart = sockd-start;
      Restart = "on-failure";
    };
  };
}
