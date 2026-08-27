{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "llm";
  cfg = config.services.llama-server-flash-next;

  # Models live on the zero ZFS pool (downloaded manually, not in the store).
  modelDir = "/zero/ai/llama";
  # Unsloth UD-Q4_K_XL (111.3 GB, 4 shards) — best quality quant that still
  # runs on 16 GB VRAM + 60 GB RAM via mmap + ZFS ARC / NVMe offload.
  modelFile = "UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf";
in
{
  options.services.llama-server-flash-next = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        llama-server — Qwen3.8-Flash-Next (qwen4exp arch) served by a llama.cpp
        build from PR #27742 (unslothai branch, not merged upstream) via the
        Vulkan (RADV) backend. Deliberately NOT started by any target: enable it
        manually with `systemctl start llama-server-flash-next`.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8088;
      description = "Port for the OpenAI-compatible endpoint (bound to 127.0.0.1).";
    };

    ctxSize = lib.mkOption {
      type = lib.types.int;
      default = 8192;
      description = "Context length in tokens. KV is cheap on qwen4exp (only 12 full-attention layers).";
    };

    nGpuLayers = lib.mkOption {
      type = lib.types.int;
      default = 8;
      description = ''
        GPU layers to offload on the RX 9070 XT 16 GB. Verified safe value is 8
        (~10.4 GB VRAM); 24 filled 16 GB and crashed. Try 12 carefully.
      '';
    };
  };

  config = lib.mkIf (enabled && cfg.enable) {
    systemd.services.llama-server-flash-next = {
      description = "llama-server Vulkan — Qwen3.8-Flash-Next UD-Q4_K_XL (qwen4exp, PR #27742)";
      # Manual start only, same as the vision llama-server.
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        User = config.users.main.name;
        # GPU access for the Vulkan (RADV) backend.
        SupplementaryGroups = [
          "render"
          "video"
        ];
        # nproc is resolved at start time via bash; llama.cpp -t defaults would
        # underuse the 9950X3D (32 threads) on the CPU-side expert compute.
        ExecStart = ''
          ${pkgs.bash}/bin/bash -c 'exec ${pkgs.llama-cpp-qwen4exp}/bin/llama-server \
            --device Vulkan0 \
            --model ${modelDir}/${modelFile} \
            --host 127.0.0.1 \
            --port ${toString cfg.port} \
            --load-mode mmap \
            --fit off \
            --n-gpu-layers ${toString cfg.nGpuLayers} \
            --ctx-size ${toString cfg.ctxSize} \
            --threads "$(nproc)" \
            --flash-attn off \
            --cache-type-k f16 \
            --cache-type-v f16 \
            --cpu-moe \
            -ot "blk\.[0-9]+\.ple_value=CPU,blk\.[0-9]+\.ple_key=CPU" \
            --jinja \
            --chat-template-kwargs "{\"reasoning_effort\":\"low\"}" \
            --log-disable'
        '';
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # Qwen3.8-Flash-Next (111 GB GGUF) depends on ZFS ARC to keep hot MoE
    # expert pages resident; the stock cap is 16 GiB. Raise it to 32 GiB.
    # Runtime-tunable without reboot via
    #   echo 32212254720 | sudo tee /sys/module/zfs/parameters/zfs_arc_max
    boot.extraModprobeConfig = "options zfs zfs_arc_max=32212254720";
  };
}
