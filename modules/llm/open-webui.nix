{
  config,
  lib,
  ...
}: let
  cfg = config.services."open-webui";
in {
  config = {
    services."open-webui" = {
      enable = lib.mkDefault true;
      host = lib.mkDefault "0.0.0.0";
      port = lib.mkDefault 11111;
      openFirewall = true;
      environment = {
        HOME = "/var/lib/open-webui";
      };
    };

    networking.firewall.allowedTCPPorts =
      lib.mkIf cfg.enable (lib.mkAfter [11111]);
  };
}
