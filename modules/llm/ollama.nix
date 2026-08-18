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
      NO_PROXY = "127.0.0.1,localhost,0.0.0.0,::1";
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.enable (lib.mkAfter [ 11434 ]);
  };
}
