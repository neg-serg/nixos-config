# llama-swap — one OpenAI-compatible endpoint in front of the local model
# stack. The `model` field of a request selects the backend: llama-swap starts
# it (or proxies to it) and shuts the previously running one down; an idle
# backend is unloaded after `ttl`. This replaces starting llama-server
# (Vulkan, vision) / llama-server-flash-next (ROCm) by hand and juggling ports;
# clients use http://127.0.0.1:9292/v1.
#
# The per-model units stay available for manual use, but do not run them while
# llama-swap owns the GPU (16 GB VRAM, one big model at a time).
#
# Games get VRAM priority: a user-level guard unloads every llama-swap model
# while a game (Proton/Wine, Steam, gamescope) is running — see the
# llama-swap-game-guard unit below.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "llm";

  # Models live on the zero ZFS pool, never in the store (multi-GB files).
  modelDir = "/zero/ai/llama";
  llamaVulkan = lib.getExe' pkgs.llama-cpp-vulkan "llama-server";
  llamaRocm = lib.getExe' pkgs.llama-cpp-qwen4exp-rocm "llama-server";

  # Vision models (Vulkan/RADV): flags mirror modules/llm/llama-server.nix.
  vision30b = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/qwen3-vl-30b-a3b-instruct-q4_k_m.gguf \
      --mmproj ${modelDir}/mmproj-qwen3-vl-30b-a3b-f16.gguf \
      --host 127.0.0.1 --port ''${PORT} -c 8192 -np 1
  '';
  vision8b = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/qwen3-vl-8b-instruct-q4_k_m.gguf \
      --mmproj ${modelDir}/mmproj-qwen3-vl-8b-f16.gguf \
      --host 127.0.0.1 --port ''${PORT} -c 8192 -np 1
  '';

  # Flash-Next (ROCm, qwen4exp): flags mirror llama-server-flash-next.nix —
  # PLE tensors on CPU, 8 GPU layers (verified safe on the RX 9070 XT), mmap.
  flashNext = ''
    ${llamaRocm} --device ROCm0 \
      --model ${modelDir}/UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      --load-mode mmap --fit off --n-gpu-layers 8 --ctx-size 8192 \
      --flash-attn off --cache-type-k f16 --cache-type-v f16 --cpu-moe \
      -ot 'blk\.[0-9]+\.ple_value=CPU,blk\.[0-9]+\.ple_key=CPU' \
      --jinja --chat-template-kwargs '{"reasoning_effort":"low"}'
  '';

  # Spark-X2.5-4B (text, 4B, hybrid sliding-window attention, 1M native ctx):
  # spark2_5 support is native in nixpkgs' llama.cpp (build 11429), so the
  # stock Vulkan binary runs it; measured ~78 tok/s generation, 32k context
  # costs ~2 GB of KV next to the 4.2 GB Q8_0 weights.
  spark4b = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/Spark-X2.5-4B-Q8_0.gguf \
      --host 127.0.0.1 --port ''${PORT} -c 32768 -np 1 --jinja
  '';

  # Gemma 4 26B A4B — the MoE tier (25.2B total, 3.8B active). Unsloth
  # UD-Q3_K_XL: ~30-40 tok/s at 64k context. Q3 instead of the QAT Q4 because
  # the desktop session holds ~3.5 GB of the 16 GB card: Q4 (13.2 GiB of
  # weights) leaves no room for KV/compute after a swap and the Vulkan backend
  # dies on the first request, while Q3 spills ~1 GB into GTT and stays up.
  # Text-only on purpose: the 1.2 GB projector does not fit; the 12B below
  # serves images. `--fit off` is required: with auto-fit, the VRAM still held
  # by the model being swapped out makes llama.cpp silently offload a few
  # layers, and a partially offloaded gemma4 backend dies on the first request.
  gemma26b = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/gemma-4-26B-A4B-it-UD-Q3_K_XL.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 65536 -np 1 --flash-attn on --fit off \
      --cache-type-k q8_0 --cache-type-v q8_0 --jinja
  '';

  # Gemma 4 12B Unified (dense) — the multimodal daily driver: the projector is
  # only 168 MB, so 32k context fits with ~5 GB of VRAM left. ~29 tok/s.
  gemma12b = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/gemma-4-12B-it-qat-UD-Q4_K_XL.gguf \
      --mmproj ${modelDir}/mmproj-gemma4-12b-F16.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 32768 -np 1 --flash-attn on --fit off \
      --cache-type-k q8_0 --cache-type-v q8_0 --jinja
  '';

  # gpt-oss-20b (MXFP4, 3.6B active) — the reasoning/tool tier and the fastest
  # of the three: ~75 tok/s at 32k with ~1.4 GB of VRAM headroom.
  gptoss = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/gpt-oss-20b-MXFP4.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 32768 -np 1 --flash-attn on --fit off --jinja
  '';

  ollamaUrl = "http://127.0.0.1:11434";

  systemdUser = config.lib.neg.systemdUser;
  swapEnabled = enabled && config.services.llama-swap.enable;

  # Game guard: games get priority on the 16 GB of VRAM. While a game (native
  # via steamapps/, Proton/Wine, or anything under gamescope) is visible, every
  # model llama-swap has loaded is unloaded every 20 s, so a leftover vision
  # model cannot OOM the game; the next request re-spawns a backend on demand.
  gameGuard = pkgs.writeShellApplication {
    name = "llama-swap-game-guard";
    runtimeInputs = [
      pkgs.coreutils # sleep in the polling loop
      pkgs.curl # GET /unload against llama-swap
      pkgs.procps # pgrep for game process detection
    ];
    text = ''
      endpoint="http://127.0.0.1:${toString config.services.llama-swap.port}/unload"
      gaming=0

      is_gaming() {
        # Match on the full command line (argv[0] may be a wrapper or a
        # renamed binary); patterns are anchored to a path separator or space.
        # Do NOT match pressure-vessel / srt-bwrap: the Steam client itself
        # keeps an srt-bwrap alive, so those matched permanently and unloaded
        # every model every 20 s while Steam was open. Proton games are still
        # caught below through their .exe process, native ones through their
        # steamapps/common/ path.
        if pgrep -f '(^|/)(gamescope|wine|wine64|wineserver|wine-preloader|wine64-preloader|lutris|heroic)( |$)' >/dev/null 2>&1; then
          return 0
        fi
        pgrep -f 'steamapps/common/|steam-launch-wrapper|\.exe' >/dev/null 2>&1
      }

      while true; do
        if is_gaming; then
          if [ "$gaming" = 0 ]; then
            echo "game detected — unloading llama-swap models"
            gaming=1
          fi
          curl -fsS -o /dev/null --max-time 5 "$endpoint" || echo "unload request failed" >&2
          sleep 20
        else
          if [ "$gaming" = 1 ]; then
            echo "game stopped"
            gaming=0
          fi
          sleep 5
        fi
      done
    '';
  };
in
{
  services.llama-swap = lib.mkIf enabled {
    enable = lib.mkDefault true;
    listenAddress = "127.0.0.1";
    port = 9292;

    settings = {
      # Flash-Next mmaps a 111 GB GGUF (-ngl 8); a cold load can take minutes.
      healthCheckTimeout = 600;
      models = {
        "qwen3-vl-30b" = {
          cmd = vision30b;
          aliases = [ "vision" ];
          # Shorter than the other models: 16 GB VRAM is tight, and a game may
          # start at any moment (the guard also unloads on game detection).
          ttl = 300;
        };
        "qwen3-vl-8b" = {
          cmd = vision8b;
          aliases = [ "vision-8b" ];
          ttl = 300;
        };
        "qwen3.8-flash-next" = {
          cmd = flashNext;
          # Cold start is ~1.5 min (111 GB mmap), so keep it longer than the
          # vision models; the game guard still unloads it for games.
          ttl = 600;
        };
        "spark-x2.5-4b" = {
          cmd = spark4b;
          aliases = [ "spark" ];
          ttl = 300;
        };
        "gemma4-26b" = {
          cmd = gemma26b;
          aliases = [ "gemma4" ];
          # Tightest model on the card (~200 MB free): release the VRAM soon.
          ttl = 300;
        };
        "gemma4-12b" = {
          cmd = gemma12b;
          aliases = [ "gemma4-vision" ];
          ttl = 600;
        };
        "gpt-oss-20b" = {
          cmd = gptoss;
          aliases = [ "gpt-oss" ];
          ttl = 600;
        };

      };

      # Ollama runs its own loading; expose it as a peer. Peer models are
      # addressable as `ollama/<name>`, and unqualified when unique.
      peers.ollama = {
        proxy = ollamaUrl;
        models = [
          "llama3.2:1b" # small smoke-test model
          "qwen3.8:27b"
          "qwen3.8:27b-plain"
          "qwen3:8b-ru"
        ];
      };
    };
  };

  # nixpkgs ships a hardened DynamicUser unit; the spawned llama.cpp children
  # need the real user (render/video groups), /dev/kfd + /dev/dri and a
  # writable shader cache, and RADV/ACO JIT dies under MemoryDenyWriteExecute.
  # Keep nixpkgs' scheduling (auto-start; the daemon itself holds no VRAM),
  # but mirror the permissive shape of the lib/llama-server.nix units.
  systemd.services.llama-swap = lib.mkIf enabled {
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = config.users.main.name;
      PrivateUsers = lib.mkForce false;
      ProtectHome = lib.mkForce false;
      ProtectSystem = lib.mkForce false;
      MemoryDenyWriteExecute = lib.mkForce false;
      SystemCallFilter = lib.mkForce [ ];
    };
  };

  # User-level guard (no root needed to call /unload): unloads llama-swap
  # models while a game runs; see the gameGuard script above.
  systemd.user.services.llama-swap-game-guard = lib.mkIf swapEnabled (
    systemdUser.mkUserService {
      presets = [
        "defaultWanted"
        "restartOnFailure"
      ];
      description = "Unload llama-swap models while a game is running";
      after = [ "network.target" ];
      serviceConfig = {
        Type = "simple";
        RestartSec = 5;
        ExecStart = lib.getExe gameGuard;
      };
    }
  );
}
