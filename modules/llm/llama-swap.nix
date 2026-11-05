# llama-swap — one OpenAI-compatible endpoint in front of the local model
# stack. The `model` field of a request selects the backend: llama-swap starts
# it (or proxies to it) and shuts the previously running one down; an idle
# backend is unloaded after `globalTTL` (60 s) or the model's own `ttl`. All
# models fit the 16 GB card except the 120B RAM tier and the `igpu` host-RAM
# tier; `qwen3-vl-30b` stays a manual per-model unit.
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
  # stays available as a manual llama-server unit.
  modelDir = "/zero/ai/llama";
  llamaVulkan = lib.getExe' pkgs.llama-cpp-vulkan "llama-server";

  # Vision model (Vulkan/RADV): abliterated Qwen3-VL-8B — the base build
  # refuses too much for this stack. 32k context, ~45 tok/s, ~3 GB of headroom.
  vision8b = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/abliterated/Qwen3-VL-8B-abliterated-Q4_K_M.gguf \
      --mmproj ${modelDir}/abliterated/mmproj-qwen3-vl-8b-ablit-f16.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 32768 -np 1 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 --jinja
  '';

  # PaddleOCR-VL-1.6 (0.47B, Apache-2.0) — document parsing: layout, tables,
  # formulas, handwritten scans. A specialized doc-VLM; a general vision model
  # loses structure. llama-server learned the paddleocr arch (#18825), and the
  # GGUF carries its chat template. One page fits 16k with room to spare.
  ocr = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/ocr/PaddleOCR-VL-1.6-GGUF.gguf \
      --mmproj ${modelDir}/ocr/PaddleOCR-VL-1.6-GGUF-mmproj.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 16384 -np 1 --flash-attn on --jinja
  '';

  # Qwen3-Embedding-0.6B (Apache-2.0) — retrieval embeddings. Qwen3 uses
  # last-token pooling, which the GGUF metadata does not set by itself.
  embed = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/embed/Qwen3-Embedding-0.6B-Q8_0.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 8192 -np 1 --embeddings --pooling last
  '';

  # Gemma 4 26B A4B — the MoE tier (25.2B total, 3.8B active), abliterated.
  # Q3_K_M on purpose: the IQ3_S build loops on multi-step prompts at greedy
  # decoding — a cold prefill falls into a repetition basin (the same prompt
  # with a warm prefix solves fine); repeat-penalty/DRY only mask it. Q3_K_M
  # does not loop: a chemistry olympiad and a math problem both finish,
  # ~105 tok/s at 32k. VRAM is tight (~16.2 GiB with the desktop open); if it
  # spills, drop -c to 16384. Text-only, the Qwen3-VL above handles images.
  # The base QAT/Q3 weights are gone: everything served here is uncensored.
  # `--fit off` is required: with auto-fit, the VRAM still held by the model
  # being swapped out makes llama.cpp silently offload a few layers, and a
  # partially offloaded gemma4 backend dies on the first request.
  gemma26b = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/abliterated/Gemma-4-26B-A4B-abliterated-Q3_K_M.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 32768 -np 1 --flash-attn on --fit off --reasoning off \
      --cache-type-k q8_0 --cache-type-v q8_0 --jinja
  '';

  # gpt-oss-20b abliterated (MXFP4, 3.6B active) — the big uncensored tier:
  # ~75-85 tok/s at 64k, tools, reasoning and arithmetic all survive the
  # abliteration. The KV cache is q8_0; f16 at 64k leaves no headroom, and -ub
  # 1024 lifts prefill from 4075 to 4546 tok/s for 170 MB.
  # `--reasoning-effort low` is mandatory: at the default effort the model
  # burns the whole token budget on reasoning and returns empty content, and
  # `--reasoning off` makes it worse.
  gptoss = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/abliterated/gpt-oss-20b-abliterated-MXFP4.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 65536 -np 1 --flash-attn on --fit off --jinja \
      --cache-type-k q8_0 --cache-type-v q8_0 -ub 1024 \
      --reasoning-effort low
  '';

  # gpt-oss-120b abliterated (MXFP4, 63.4 GB) — the RAM tier: the model is 4x
  # the card, so only 4 layers run on the GPU (attention + their expert layers,
  # ~6.9 GiB model buffer, ~10.5 GiB total with the desktop) and the other 32
  # stay mmap'd, read from page cache / NVMe on demand. 5.1B active gives
  # 6-8.5 tok/s decode on a cold page cache and ~11.5 once the file is warm
  # (measured 2026-11-05), but prefill is CPU-bound at ~19 tok/s: a 2k prompt
  # costs ~100 s, a 20k agent prompt ~18 min. NOT --n-cpu-moe here: it mallocs
  # the expert weights, and ~52 GB of anonymous memory does not fit next to the
  # desktop, so the 507 GB swap becomes the hot path (measured 25-27 -> 7.55
  # tok/s in llama.cpp#26110). mmap'd pages, by contrast, are evictable.
  # `-ngl 4`, not 5: at 5 the card sat at 96% with the desktop open.
  gptoss120 = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/abliterated/gpt-oss-120b-abliterated-MXFP4_MOE.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -ngl 4 -c 16384 -np 1 --flash-attn on --fit off --jinja \
      --cache-type-k q8_0 --cache-type-v q8_0 -ub 512 \
      --reasoning-effort low
  '';

  # Qwen3.8-Flash-Next abliterated v2 (Swift IQ3_S, 78 GB in two shards, split
  # GGUF: point llama.cpp at -00001). 180B total but only 6B active: 48 layers
  # of ~0.95 GiB (the hot set, ~45 GiB; a token reads ~0.82 GiB of it — 10 of
  # 512 experts across 48 layers) plus a 26.8 GiB per-token embedding table
  # (320M rows, one row touched per token, so it stays cold). Four layers stay
  # on the card (~4.8 GiB buffer, 8.1 GiB with the desktop), the rest is mmap'd
  # from /zero. Measured 2026-11-05 with `llama-bench` (tg64, q8_0 KV, fa on):
  # decode 4.6 tok/s cold / 7.7 warm at -ub 512, 8.4-9.1 at -ub 1024; prefill
  # (pp1024) 80 tok/s at -ub 512, 133 at -ub 1024. `-ub 2048` is a trap (41
  # tok/s) and `-ngl` 8/10 buys nothing (7.6/7.4 warm): decode is bound by
  # reading expert weights from RAM, not by GPU compute. Speculative decoding
  # does not pay either — a Qwen3.5-4B draft (same 248320 vocab) costs 9%
  # because acceptance is low, `--spec-type ngram-simple` is noise, and
  # `draft-mtp` is rejected (no MTP head in this GGUF). `--reasoning off` is
  # mandatory: it thinks by default and the reply arrives with an empty
  # `content`.
  qwen38next = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/abliterated/qwen38-flash-next-iq3s/Swift-Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -ngl 4 -c 32768 -np 1 --flash-attn on --fit off --reasoning off --jinja \
      --cache-type-k q8_0 --cache-type-v q8_0 -ub 1024
  '';

  # Qwen3.6-35B-A3B abliterated (i1/IQ2_S) — the strongest model that fits the
  # 16 GB card next to the desktop: ~55 tok/s at 64k, text-only. The dynamic
  # IQ2 keeps attention and shared experts at higher precision; a Q3 build
  # (IQ3_XXS) would need ~13.6 GB and does not fit with Steam open.
  qwen36 = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/abliterated/Qwen3.6-35B-A3B-abliterated-IQ2_S.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 65536 -np 1 --flash-attn on --fit off --reasoning off \
      --cache-type-k q8_0 --cache-type-v q8_0 -ub 1024 --jinja
  '';

  # Qwen3.8-27B abliterated (IQ3_S, ~3.5 bpw) — the quality tier: dense 27B,
  # the highest bits-per-weight of anything served here, text-only. Dense
  # attention makes the KV cache expensive: q8_0 caches only leave room for
  # ~8k, so both run q4_0 and the context stops where the 16 GB card does:
  # 24k = ~15 GiB with the desktop open, 30-36 tok/s at a 20k prompt (prefill
  # ~980 tok/s; 32k spills to ~4 tok/s). 24k is the floor, not comfort — the
  # agent harness prompt alone is ~20k tokens and 16k rejected it outright.
  # `--reasoning off` is mandatory: without it the reply arrives with an
  # empty `content` (everything goes to reasoning).
  qwen38 = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/abliterated/Qwen3.8-27B-abliterated-IQ3_S.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 24576 -np 1 --flash-attn on --fit off --reasoning off \
      --cache-type-k q4_0 --cache-type-v q4_0 --jinja
  '';

  # Qwen3.5-4B abliterated (Q8_0) — the fast, long-context tier: dense 4B,
  # hybrid attention (8 of 32 layers full), so KV is only ~17 KiB/token at
  # q8_0 and the native 256k window costs ~9.3 GiB of the card (~11.7 GiB
  # total with the desktop). Verified end-to-end on a 104k-token prompt: the
  # needle came back, prefill 2890 tok/s (~36 s), decode 70 tok/s at that
  # depth and ~95-100 short. The ~4 GiB left over is fine for the desktop
  # but not for a game plus OBS: drop to -c 131072 (~6.8 GiB) if a client
  # OOMs. `--reasoning off` is mandatory: with thinking on it spends the
  # whole token budget inside reasoning_content and returns empty content
  # (observed at 6000 tokens, finish=length).
  qwen35_4b = ''
    ${llamaVulkan} --device Vulkan0 \
      -m ${modelDir}/abliterated/Qwen3.5-4B-abliterated-Q8_0.gguf \
      --host 127.0.0.1 --port ''${PORT} \
      -c 262144 -np 1 --flash-attn on --fit off --reasoning off \
      --cache-type-k q8_0 --cache-type-v q8_0 -ub 1024 --jinja
  '';

  # Spark-X2.6-4B abliterated (Q4) — the CPU-only tier: no VRAM at all, so it
  # can be used while a game owns the card. ~22 tok/s with 4 threads, which
  # leaves 28 of the 32 hardware threads to the game. The game guard skips it.
  # 64k, not the 16k it started at: the model is 1M-native with sliding-window
  # attention and its f16 KV is ~42 KB/token (5.2 GiB RSS at 64k, 3.3 GiB at
  # 16k), while CPU prefill runs at 800-1000 tok/s, so a 20k prompt costs ~25 s
  # once and is then served from the prompt cache. Generation slows with the
  # context: ~22 tok/s short, ~8 tok/s on a 40k prompt. 16k could not hold the
  # agent harness prompt at all (~20k tokens: system prompt + tools + skills),
  # which showed up as `request (20126 tokens) exceeds the available context
  # size (16384 tokens)`.
  tiny = ''
    ${llamaVulkan} -m ${modelDir}/abliterated/Spark-X2.6-4B-abliterated-Q4_K_M.gguf \
      -ngl 0 -t 4 -c 65536 -np 1 --jinja --reasoning off \
      --host 127.0.0.1 --port ''${PORT}
  '';

  # Spark-X2.6-4B on the iGPU (Radeon 610M, Granite Ridge, 2 CU) — the third
  # tier: no dGPU VRAM at all, so it can serve while the 16 GB card is busy
  # (and while `tiny` is not the flavour you want). Measured on 2026-11-05 with
  # this exact GGUF: decode 10.9 tok/s, i.e. the same as `tiny` on 4 threads
  # (10.7), but prefill is ~10x slower (73 vs 742 tok/s) — the APU is
  # bandwidth-bound on shared DDR5 and RADV has no coopmat path for RDNA2.
  # Hence 8k, not 64k: a 20k prompt (the agent harness) costs ~4.5 min here
  # versus ~27 s on CPU. Use it for short-output work — labels, JSON
  # extraction, tagging — not for prompt-heavy requests. Vulkan1 is the 610M;
  # Vulkan0 is the RX 9070 XT (`llama-server --list-devices`). `-t 4` caps
  # host-side work only, once the layers live on the APU. The game guard still
  # unloads this model while a game runs (it competes for the same memory
  # bandwidth); only `tiny` is exempt.
  igpu = ''
    ${llamaVulkan} --device Vulkan1 -ngl 99 \
      -m ${modelDir}/abliterated/Spark-X2.6-4B-abliterated-Q4_K_M.gguf \
      -t 4 -c 8192 -np 1 --jinja --reasoning off \
      --host 127.0.0.1 --port ''${PORT}
  '';

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
      pkgs.jq # read /running, so the CPU-only model is left alone
      pkgs.procps # pgrep for game process detection
    ];
    text = ''
      base="http://127.0.0.1:${toString config.services.llama-swap.port}"
      endpoint="$base/unload"
      running="$base/running"
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
            echo "game detected — unloading GPU models"
            gaming=1
          fi
          # llama-swap keeps one model resident: leave the CPU-only `tiny`
          # alone (it holds no VRAM) and unload anything else.
          model=$(curl -fsS --max-time 5 "$running" | jq -r '.running[0].model // empty' 2>/dev/null)
          if [ "$model" != "tiny" ]; then
            curl -fsS -o /dev/null --max-time 5 "$endpoint" || echo "unload request failed" >&2
          fi
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
      # Idle backends unload after a minute: the card is shared with the
      # desktop (~4 GB with Steam and Vivaldi) and with games, so nothing may
      # sit on it unused. A cold load costs 8-20 s, so a minute is still long
      # enough not to reload between messages.
      globalTTL = 60;
      models = {
        "qwen3-vl-8b-abliterated" = {
          cmd = vision8b;
          aliases = [
            "vision"
            "vision-8b"
            "qwen3-vl-8b"
          ];
        };
        "gemma4-26b-abliterated" = {
          cmd = gemma26b;
          aliases = [
            "gemma4"
            "gemma4-26b"
          ];
        };
        "gpt-oss-20b-abliterated" = {
          cmd = gptoss;
          aliases = [
            "gpt-oss"
            "gpt-oss-20b"
            "uncensored"
          ];
        };
        "qwen3.6-35b-abliterated" = {
          cmd = qwen36;
          aliases = [
            "strong"
            "qwen3.6"
          ];
        };
        "gpt-oss-120b-abliterated" = {
          cmd = gptoss120;
          # 63 GB + ~55 s cold start: keep it resident for 15 min instead of
          # letting the 60 s global TTL force a reload between messages.
          ttl = 900;
          aliases = [
            "gpt-oss-120"
            "big"
          ];
        };
        "qwen3.8-flash-next-abliterated" = {
          cmd = qwen38next;
          ttl = 900;
          aliases = [
            "qwen3.8-flash"
            "next"
          ];
        };
        "qwen3.8-27b-abliterated" = {
          cmd = qwen38;
          aliases = [
            "qwen3.8"
            "ru"
          ];
        };
        "qwen3.5-4b-abliterated" = {
          cmd = qwen35_4b;
          aliases = [
            "qwen3.5"
            "quick"
          ];
        };

        "tiny" = {
          cmd = tiny;
          aliases = [
            "cheap"
            "spark-cpu"
          ];
        };

        "igpu" = {
          cmd = igpu;
          aliases = [
            "spark-igpu"
            "cheap-igpu"
          ];
        };

        # Specialized small models: loaded on a request, unloaded after the
        # TTL. The editor's FIM backend is a separate service (modules/llm/fim.nix).
        "ocr" = {
          cmd = ocr;
          ttl = 600;
          aliases = [
            "paddleocr"
            "document"
          ];
        };
        "embed" = {
          cmd = embed;
          ttl = 600;
          aliases = [ "embeddings" ];
        };
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
