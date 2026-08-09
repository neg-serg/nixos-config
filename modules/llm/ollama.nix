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
      # RX 9070 XT (Navi 48, gfx1201) — the pinned nixpkgs' ROCm ships
      # gfx1201 code objects, so no HSA_OVERRIDE_GFX_VERSION is needed.
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.enable (lib.mkAfter [ 11434 ]);
  };
}
