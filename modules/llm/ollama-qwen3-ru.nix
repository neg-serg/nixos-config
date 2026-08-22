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
  ensure = pkgs.writeShellScript "ollama-qwen3-ru-ensure" ''
    set -eu
    export OLLAMA_MODELS=/zero/ai/ollama
    export OLLAMA_HOST=127.0.0.1:11434
    mkdir -p "$OLLAMA_MODELS"

    cp "${modelfile}" "${modelfileOut}"
    chmod 0664 "${modelfileOut}"

    # Wait for the ollama API to become reachable (max ~60s).
    i=0
    until ${ollama} list >/dev/null 2>&1; do
      i=$((i+1))
      [ "$i" -ge 60 ] && break
      sleep 1
    done

    # Base model must be present; create the tuned variant only if missing.
    if ${ollama} list 2>/dev/null | grep -q '^${base} '; then
      if ! ${ollama} list 2>/dev/null | grep -q '^${model} '; then
        ${ollama} create ${model} -f "${modelfileOut}"
      fi
    fi
  '';
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
