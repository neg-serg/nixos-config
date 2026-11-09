{
  config,
  lib,
  ...
}:
let
  cfg = config.services.ollama;
  enabled = config.lib.neg.enabled "llm";
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

    # registry.ollama.ai is flaky/blocked from this region (TLS handshake timeouts,
    # e.g. gemma4:26b manifest). Route model downloads via the sing-box socks5 proxy.
    systemd.services.ollama.environment = {
      HTTPS_PROXY = "socks5://127.0.0.1:10808";
      ALL_PROXY = "socks5://127.0.0.1:10808";
      # Cloudflare R2 (the blob CDN every manifest points at) must go through the
      # same proxy: measured 2026-11-01, `deepseek-r1:32b` stalled at "pulling
      # manifest" for a minute and the daemon logged "net/http: TLS handshake
      # timeout" against `*.r2.cloudflarestorage.com` on every part. The proxy
      # itself answers R2 in 0.17 s (HTTP 400 on the bare bucket, i.e. TLS and
      # routing are fine), while a direct connection times out — so the old
      # exception, which assumed sing-box could not carry R2, only broke pulls.
      NO_PROXY = "127.0.0.1,localhost,0.0.0.0,::1";

      # 16 GB VRAM (RX 9070 XT) tuning: keep one model resident, cap default
      # context to 32k and quantize the KV cache to Q8_0 so qwen3:8b runs fully
      # on GPU (≈11 GB) instead of spilling to CPU. OLLAMA_CONTEXT_LENGTH is a
      # per-request default; a client can still pass a smaller num_ctx.
      # Keep-alive is short (5m): the ~11 GB vision model must not sit in VRAM
      # for long, or Proton games (UE5 titles at 4K+Lumen easily need 6+ GB) get
      # pushed into GTT/system memory and stutter hard. 5m keeps back-to-back
      # chat/vision responses warm while freeing VRAM minutes after the last use.
      # Manual escape hatch: `ollama stop qwen3:8b-q8_0` before gaming.
      OLLAMA_NUM_PARALLEL = "1";
      OLLAMA_MAX_LOADED_MODELS = "1";
      OLLAMA_CONTEXT_LENGTH = "32768";
      OLLAMA_KV_CACHE_TYPE = "q8_0";
      OLLAMA_KEEP_ALIVE = "5m";
    };

    # The bundled llama.cpp server logs every slot operation at INFO even when
    # idle ("slot get_availabl", "srv update_slots: all slots are idle"):
    # ~13.6k lines/day, enough to trip journald's RateLimitBurst ("Suppressed N
    # messages from ollama.service"). Warnings and errors are what this unit
    # must surface, so cap the journal at warning. LogLevelMax only has an
    # effect on system units: journald reads /run/systemd/units/log-level-max:<unit>,
    # which the user manager cannot write (verified 2026-11-10).
    systemd.services.ollama.serviceConfig.LogLevelMax = "warning";

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.enable (lib.mkAfter [ 11434 ]);
  };
}
