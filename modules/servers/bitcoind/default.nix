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
      warnings = [
        "servers/bitcoind: enabling instance '${cfg.instance}' on port ${toString cfg.p2pPort}"
      ];
    }
    {
      services.bitcoind = lib.genAttrs [cfg.instance] (_: {
        enable = true;
        dataDir = cfg.dataDir;
        port = cfg.p2pPort;
      });
    }
    {
      networking.firewall.allowedTCPPorts = lib.mkAfter [cfg.p2pPort];
    }
  ]);
}
