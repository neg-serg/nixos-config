{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.net.lan-proxy;
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
      ExecStart = "${pkgs.dante}/bin/sockd -f ${pkgs.writeText "sockd.conf" ''
        internal: 0.0.0.0 port = 10809
        external: 0.0.0.0
        method: none
        clientmethod: none
        user.notprivileged: nobody
        client pass {
          from: 0.0.0.0/0 to: 0.0.0.0/0
          log: error
        }
        pass {
          from: 0.0.0.0/0 to: 0.0.0.0/0
          log: error
        }
      ''}";
      Restart = "on-failure";
    };
  };
}
