{ config, lib, pkgs, ... }:

let
  cfg = config.services.ncps;
  format = pkgs.formats.toml {};
  configFile = format.generate "ncps.toml" {
    cache = cfg.cache;
    upstream = cfg.upstream;
  };
in
{
  options.services.ncps = {
    enable = lib.mkEnableOption "Nix Cache Proxy Service";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.ncps;
      description = "The ncps package to use.";
    };

    cache = lib.mkOption {
      type = lib.types.submodule {
        freeformType = format.type;
      };
      default = {};
      description = "Cache configuration section.";
    };

    upstream = lib.mkOption {
      type = lib.types.submodule {
        freeformType = format.type;
      };
      default = {};
      description = "Upstream configuration section.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.ncps = {
      description = "Nix Cache Proxy Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/ncps serve --config ${configFile}";
        Restart = "always";
        DynamicUser = true;
        StateDirectory = "ncps";
        CacheDirectory = "ncps";
      };
    };
  };
}
