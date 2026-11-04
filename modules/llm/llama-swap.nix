# llama-swap — one OpenAI-compatible endpoint in front of the local model
# stack. The `model` field of a request selects the backend: llama-swap starts
# it (or proxies to it) and shuts the previously running one down; an idle
# backend is unloaded after `globalTTL` (120 s). Only models that fit the 16 GB
# card are exposed here; the oversized ones stay as manual per-model units.
# Clients use http://127.0.0.1:9292/v1.
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
  # Only models that fit the 16 GB card are exposed here. qwen3-vl-30b (18 GB)
  # and Flash-Next (111 GB, CPU-MoE) stay available as manual units
  # (llama-server and llama-server-flash-next).
  modelDir = "/zero/ai/llama";
  llamaVulkan = lib.getExe' pkgs.llama-cpp-vulkan "llama-server";

  # Vision model (Vulkan/RADV): flags mirror modules/llm/llama-server.nix.
  vision8b = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/qwen3-vl-8b-instruct-q4_k_m.gguf \
      --mmproj ${modelDir}/mmproj-qwen3-vl-8b-f16.gguf \
      --host 127.0.0.1 --port ''${PORT} -c 8192 -np 1
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

  # Qwen3.8-4B Distill Heretic — the uncensored small tier: a Qwen3.8
  # distillation into Qwen3.5-4B, abliterated with Heretic v1.4.0. ~56-60 tok/s
  # with text + vision at 32k. Thinking is off: at 4B it costs latency without
  # helping the tasks this model is for (translation, summaries, JSON
  # extraction, classification, short creative text). It is weak at arithmetic
  # and multi-step reasoning — do not route those here.
  qwenUncensored = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/abliterated/Qwen3.8-4B-Distill-Heretic-Q4_K_M.gguf \
      --mmproj ${modelDir}/abliterated/qwen38-mmproj-f16.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 32768 -np 1 --flash-attn on --fit off --reasoning off --jinja
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
      healthCheckTimeout = 600;
      # Idle backends unload after two minutes: the card is shared with the
      # desktop (~3.5 GB) and with games, so nothing may sit on it unused.
      globalTTL = 120;
      models = {
        "qwen3-vl-8b" = {
          cmd = vision8b;
          aliases = [
            "vision"
            "vision-8b"
          ];
        };
        "spark-x2.5-4b" = {
          cmd = spark4b;
          aliases = [ "spark" ];
        };
        "gemma4-26b" = {
          cmd = gemma26b;
          aliases = [ "gemma4" ];
        };
        "gemma4-12b" = {
          cmd = gemma12b;
          aliases = [ "gemma4-vision" ];
        };
        "gpt-oss-20b" = {
          cmd = gptoss;
          aliases = [ "gpt-oss" ];
        };
        "qwen3.8-4b-abliterated" = {
          cmd = qwenUncensored;
          aliases = [ "uncensored" ];
        };
      };

      # Ollama runs its own loading; expose it as a peer. Peer models are
      # addressable as `ollama/<name>`, and unqualified when unique. Only
      # models that fit the card are listed — a 17 GB ollama tag spills to CPU.
      peers.ollama = {
        proxy = ollamaUrl;
        models = [
          "llama3.2:1b" # small smoke-test model
          "qwen3:8b-ru" # 5.2 GB, fully on the GPU
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
