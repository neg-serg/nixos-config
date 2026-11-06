{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.net.proxy;

  # Xray is a manual, rarely started core. Keep the CLI as an on-demand
  # launcher and give the unit a wrapper that materialises the GC root before
  # exec, so `systemctl start xray` keeps working while the binary stays out of
  # the system closure.
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") {
    inherit pkgs;
    nix = config.nix.package;
  };
  xray = onDemand {
    name = "xray";
    attr = "xray";
  };

  # Systemd gets a wrapper rather than the launcher itself: the unit has no
  # argv, so the daemon flags are baked here. Exec goes through the launcher,
  # which materialises the root on the first start (as `neg`, HOME set by
  # systemd).
  xrayService = pkgs.writeShellScriptBin "xray-service" ''
    exec ${xray}/bin/xray run -config /home/neg/.config/sing-box-tun/config.json
  '';
in
lib.mkIf cfg.enable {
  environment.systemPackages = [
    xray # VLESS/Reality-capable proxy core (built on first call)
  ];

  systemd.services.xray = {
    description = "Xray local SOCKS5 proxy (127.0.0.1:10808)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    # No autostart, and deliberately no ExecStartPre: it used to run
    # `fuser -k 10808/tcp`, which killed the user's sing-box proxy (also on
    # 10808) on every activation — each `nh os switch` took API access down
    # with it, then the unit crash-looped until the next manual restart. The
    # xray unit stays manual; picking a port that does not clash with the
    # sing-box SOCKS inbound is the caller's job.
    wantedBy = lib.mkForce [ ];
    serviceConfig = {
      Type = "simple";
      User = "neg";
      ExecStart = "${xrayService}/bin/xray-service";
    };
  };
}
