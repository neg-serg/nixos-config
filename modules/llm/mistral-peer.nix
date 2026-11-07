# Remote Mistral API tier for llama-swap. Leanstral 1.5 (119B total, 6.5B
# active) does not fit this host: 16 GB of VRAM and 60 GB of RAM against a
# 72 GB Q4 file, measured at ~1.5 tok/s when mmap'd from /zero. Serving it
# from Mistral's OpenAI-compatible API keeps the local card free and gives the
# model the context it was trained for.
#
# Peer models are addressed as `mistral/<model-id>`, so the catalog entry is
# `mistral/labs-leanstral-1-5` with the `leanstral`/`lean` aliases.
#
# The API key is never in the Nix store. The sops value is a full
# `MISTRAL_API_KEY=...` line; systemd reads the decrypted 0400 file as root
# before dropping to the service user, and llama-swap substitutes
# `${env.MISTRAL_API_KEY}` from that environment when it loads the peer.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "llm" && config.services.llama-swap.enable;
in
{
  config = lib.mkIf enabled {
    sops.secrets."mistral-env" = {
      sopsFile = config.lib.neg.path "secrets/mistral.sops.yaml";
      owner = "root";
      mode = "0400";
    };

    services.llama-swap.settings.peers.mistral = {
      proxy = "https://api.mistral.ai";
      apiKey = "\${env.MISTRAL_API_KEY}";
      models = [ "labs-leanstral-1-5" ];
    };

    # `llama-swap -validate` runs in the Nix build sandbox, where the sops
    # key is not in the environment and the peer's `${env.MISTRAL_API_KEY}`
    # macro would abort the build. The fallback below is a dummy, not a
    # secret; at runtime the EnvironmentFile value is already set, so `:-`
    # keeps the real key and only the validator sees the placeholder.
    services.llama-swap.package = pkgs.writeShellApplication {
      name = "llama-swap";
      text = ''
        export MISTRAL_API_KEY="''${MISTRAL_API_KEY:-REPLACE_ME}"
        exec ${pkgs.llama-swap}/bin/llama-swap "$@"
      '';
    };

    systemd.services.llama-swap.serviceConfig.EnvironmentFile = [
      config.sops.secrets."mistral-env".path
    ];
  };
}
