{
  config,
  lib,
  ...
}: let
  cfg = config.services.ollama;
in {
  config = {
    services.ollama = {
      enable = lib.mkDefault true;
      host = lib.mkDefault "0.0.0.0";
      port = lib.mkDefault 11434;
      acceleration = lib.mkDefault "rocm";
      rocmOverrideGfx = lib.mkDefault "11.0.1";
      environmentVariables = lib.mkDefault {
        HCC_AMDGPU_TARGET = "gfx1101";
      };
    };

    networking.firewall.allowedTCPPorts =
      lib.mkIf cfg.enable (lib.mkAfter [11434]);
  };
}
