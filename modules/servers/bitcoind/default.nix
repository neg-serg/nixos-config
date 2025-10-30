##
# Module: servers/bitcoind
# Purpose: Wire servicesProfiles.bitcoind → services.bitcoind.<instance> and firewall.
# Key options: cfg = config.servicesProfiles.bitcoind (enable, instance, dataDir, p2pPort)
# Dependencies: NixOS bitcoind module (services.bitcoind.*)
{
  lib,
  config,
  ...
}: let
  cfg = config.servicesProfiles.bitcoind or {enable = false;};
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.bitcoind = lib.genAttrs [cfg.instance] (_: {
        enable = true;
        dataDir = cfg.dataDir;
        port = cfg.p2pPort;
        # Route logs to journald and keep the on-disk debug.log from growing unbounded
        # - printtoconsole=1 ensures logs go to stdout/stderr (systemd → journald → Loki/Promtail)
        # - shrinkdebugfile=1 trims debug.log on startup if present
        extraConfig = ''
          printtoconsole=1
          shrinkdebugfile=1
        '';
      });
    }
    {
      networking.firewall.allowedTCPPorts = lib.mkAfter [cfg.p2pPort];
    }
    {
      # Rotate bitcoind debug.log if it is written despite printtoconsole
      services.logrotate.settings."${cfg.dataDir}/debug.log" = {
        frequency = "weekly";
        rotate = 8;
        missingok = true;
        compress = true;
        delaycompress = true;
        copytruncate = true;
        size = "50M";
      };
    }
  ]);
}
