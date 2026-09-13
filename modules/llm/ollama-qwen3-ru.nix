{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "llm";
  base = "qwen3:8b";
  model = "qwen3:8b-ru";
  ollama = lib.getExe pkgs.ollama-rocm;
  modelfile = ../../files/ai/Modelfile.qwen3-8b-ru;
  modelfileOut = "/zero/ai/ollama/Modelfile.qwen3-8b-ru";

  # Tuned interactive Qwen3 8B: RU system prompt + sane sampler defaults,
  # built from the locally stored qwen3:8b (reuses its blobs). The unit is
  # idempotent — it only creates the model when missing, so re-runs are no-ops.
  ensure = pkgs.writeShellScript "ollama-qwen3-ru-ensure" (
    builtins.readFile (
      pkgs.replaceVars ./ollama-qwen3-ru/ensure.sh {
        inherit
          base
          modelfileOut
          model
          ollama
          ;
        modelfile = pkgs.copyPathToStore modelfile;
      }
    )
  );
in
{
  config = lib.mkIf enabled {
    systemd.services.ollama-qwen3-ru = {
      description = "Ensure tuned qwen3:8b-ru model in the local ollama store";
      after = [
        "ollama.service"
        "network.target"
      ];
      wants = [ "ollama.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = ensure;
      };
    };
  };
}
