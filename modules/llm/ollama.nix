{
  config,
  lib,
  ...
}:
let
  cfg = config.services.ollama;
  enabled = config.features.llm.enable or false;
in
{
  config = lib.mkIf enabled {
    services.ollama = {
      enable = lib.mkDefault true;
      host = lib.mkDefault "0.0.0.0";
      port = lib.mkDefault 11434;
      acceleration = lib.mkDefault "rocm";
      rocmOverrideGfx = lib.mkDefault "11.0.0"; # Navi 31 / RX 7900 XTX
      environmentVariables = lib.mkDefault {
        HCC_AMDGPU_TARGET = "gfx1100"; # RX 7900 XTX
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.enable (lib.mkAfter [ 11434 ]);
  };
}
