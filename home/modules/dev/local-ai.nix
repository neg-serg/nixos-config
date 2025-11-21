{
  lib,
  pkgs,
  config,
  systemdUser,
  ...
}: let
  cfg = config.features.dev.ai or {};
in {
  config = lib.mkIf (cfg.enable or false) {
    # Local AI (Ollama) as a user service
    systemd.user.services."local-ai" = lib.mkMerge [
      {
        Unit = {Description = "Local AI (Ollama)";};
        Service = {
          ExecStart = "${pkgs.ollama}/bin/ollama serve";
          Environment = [
            # For LocalAI compatibility (unused by Ollama shim)
            "MODELS_PATH=${config.xdg.dataHome}/localai/models"
            # Effective for Ollama
            "OLLAMA_MODELS=${config.xdg.dataHome}/ollama"
            "OLLAMA_HOST=127.0.0.1:11434"
          ];
          Restart = "on-failure";
          RestartSec = "2s";
        };
      }
      (systemdUser.mkUnitFromPresets {presets = ["defaultWanted"];})
    ];
  };
}
