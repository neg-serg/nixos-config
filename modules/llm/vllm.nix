{
  config,
  lib,
  pkgs,
  ...
}:
# vLLM — OpenAI-compatible LLM server on the RX 9070 XT (ROCm, gfx1201).
#
# The package is `pkgs.vllmRocmEnv` (packages/vllm-rocm/default.nix): vLLM
# 0.24.0 built against the ROCm torch 2.12.0 closure that torch-rocm already
# provides. Nothing here is auto-started — like llama-server, the unit exists
# for `systemctl start vllm` and stays out of the boot path:
#
#     systemctl start vllm          # serves services.vllm.model on 127.0.0.1:8004
#     journalctl -u vllm -f
#     curl http://127.0.0.1:8004/v1/models
#
# One-off runs against another model go through the `vllm` CLI directly:
#
#     vllm serve <hf-repo-or-local-path> --port 8004
let
  enabled = config.lib.neg.enabled "llm";
  cfg = config.services.vllm;

  # Weights, the HF cache and the Triton kernel cache live on the zero ZFS pool,
  # never on system disks: model files are multi-GB and nix GC cannot reclaim
  # them. The directory is created by the activation script in
  # modules/llm/default.nix (tmpfiles refuses paths under /zero/ai).
  cacheDir = "/zero/ai/vllm";

  # The wrapper sheds two inherited variables that break the environment:
  #   PYTHONPATH      — the login shell may leak a py3.13 venv path, which breaks
  #                     numpy inside the 3.14 environment (same gotcha as the
  #                     torch-rocm CLI);
  #   LD_LIBRARY_PATH — the shell exports the *system* glibc (2.44), while this
  #                     environment is built against the pinned nixpkgs' 2.42;
  #                     mixing them aborts with "undefined symbol:
  #                     __pointer_chk_guard, version GLIBC_PRIVATE". systemd
  #                     units start clean, so the service never sees this.
  vllmCli = pkgs.writeShellScriptBin "vllm" ''
    exec env -u PYTHONPATH -u LD_LIBRARY_PATH ${pkgs.vllmRocmEnv}/bin/vllm "$@"
  '';
in
{
  options.services.vllm = {
    # Present by default when the llm feature is on; the unit is never
    # auto-started (mkService emits no wantedBy) — start it manually.
    enable =
      (lib.mkEnableOption ''
        vLLM — local OpenAI-compatible LLM server (ROCm, gfx1201).

        Deliberately NOT started by any target: `systemctl start vllm` when you
        want it. Pulls the ROCm vLLM environment (~5 GB closure) into the system
        profile.
      '')
      // {
        default = true;
      };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8004; # 8000 omnirouter, 8001 piper, 8002 whisper, 8003 colibri
      description = "Port for the OpenAI-compatible endpoint (bound to 127.0.0.1).";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "Qwen/Qwen3-4B-Instruct-2507";
      example = "Qwen/Qwen3-8B-AWQ";
      description = ''
        Model to serve: a Hugging Face repo id (downloaded into
        `${cacheDir}/hub` on first start) or an absolute path to a local
        checkpoint directory.

        VRAM is 16 GB: bf16 fits up to ~8B, int4 (AWQ/GPTQ) up to ~14B.
      '';
    };

    gpuMemoryUtilization = lib.mkOption {
      type = lib.types.float;
      default = 0.6;
      description = ''
        Fraction of the 16 GB of VRAM vLLM may claim (`--gpu-memory-utilization`).

        The default is well below vLLM's own 0.92: the desktop compositor and
        Ollama share the card and already hold ~5.5 GB, so 0.92 makes the engine
        abort at startup ("free memory … less than desired"). Raise it for a
        bigger KV cache after `ollama stop <model>`; the whole card is never
        available while a desktop session is running.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        VLLM_ROCM_USE_AITER = "0";
      };
      description = ''
        Extra environment variables for the server unit (engine knobs such as
        `VLLM_ROCM_USE_AITER`, `HSA_OVERRIDE_GFX_VERSION`, `HF_TOKEN`).
        `HF_HOME` and `VLLM_CACHE_ROOT` are set automatically.
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "--max-model-len"
        "32768"
        "--gpu-memory-utilization"
        "0.85"
      ];
      description = "Extra arguments appended to `vllm serve`.";
    };
  };

  config = lib.mkIf (enabled && cfg.enable) {
    environment.systemPackages = [ vllmCli ];

    systemd.services.vllm =
      let
        # Same unit skeleton as llama-server: manual start, runs as the main
        # user, GPU access through the render/video supplementary groups.
        unit = config.lib.neg.llamaServer.mkService {
          description = "vLLM ROCm (gfx1201) OpenAI-compatible server";
          user = config.users.main.name;
          execStart = lib.concatStringsSep " " (
            [
              "${vllmCli}/bin/vllm"
              "serve"
              (lib.escapeShellArg cfg.model)
              "--host"
              "127.0.0.1"
              "--port"
              (toString cfg.port)
              "--gpu-memory-utilization"
              (builtins.toJSON cfg.gpuMemoryUtilization)
              "--download-dir"
              (lib.escapeShellArg "${cacheDir}/hub")
            ]
            ++ map lib.escapeShellArg cfg.extraArgs
          );
        };
      in
      unit
      // {
        serviceConfig = unit.serviceConfig // {
          Environment = lib.mapAttrsToList (name: value: "${name}=${value}") (
            {
              HF_HOME = "${cacheDir}/hf"; # weight + tokenizer cache
              VLLM_CACHE_ROOT = "${cacheDir}/cache"; # Triton/JIT kernel cache
            }
            // cfg.settings
          );
          LimitNOFILE = 65536;
        };
      };
  };
}
