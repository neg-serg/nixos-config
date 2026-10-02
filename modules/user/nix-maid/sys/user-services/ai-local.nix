{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.gui;
  # Module-shaped systemd user units (lib/systemd-user.nix)
  systemdUser = config.lib.neg.systemdUser;
in
lib.mkIf (cfg.enable or false) {
  systemd.user.services = {
    # Local AI (Ollama) — user-level fallback for hosts WITHOUT the system
    # ollama service (which binds the same 11434 port and serves the same
    # store). Models live on the zero pool, never on the system disk.
    "local-ai" =
      lib.mkIf ((config.lib.neg.enabled "llm") && !(config.services.ollama.enable or false))
        (
          systemdUser.mkUserService {
            presets = [
              "defaultWanted"
              "restartOnFailure"
            ];
            description = "Local AI (Ollama)";
            serviceConfig = {
              ExecStart = "${lib.getExe pkgs.ollama} serve"; # Get up and running with large language models locally
              Environment = [
                # For LocalAI compatibility
                "MODELS_PATH=/zero/ai/localai"
                # Effective for Ollama
                "OLLAMA_MODELS=/zero/ai/ollama"
                "OLLAMA_HOST=127.0.0.1:11434"
              ];
              RestartSec = "2s";
            };
          }
        );
  };
}
