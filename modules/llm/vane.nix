# Module: llm/vane
# Purpose: Vane (formerly Perplexica) — a self-hosted, Perplexity-style AI answer
#          engine that returns cited answers from live web search. Runs fully
#          local on the existing ollama service (no API keys, no cloud), so it
#          is a drop-in replacement for the paid Perplexity tier for the LAN.
#
# Key options: services.vane.enable (default: off).
# Gating:      requires the "llm" domain (config.lib.neg.enabled "llm") — the
#              same master switch that already gates modules/llm/ollama.nix.
#
# Runtime model: Vane has no nixpkgs package, so it is deployed as a container.
# odin runs containers rootless under the `neg` user session (see the dockur
# windows VM: hosts/odin/virtualisation + libpod scopes), NOT as root systemd
# services. ollama is the exception because nixpkgs ships it natively. To stay
# inside the repo's existing container runtime, Vane is a neg *user* systemd
# unit that drives `podman run` — it starts with the neg session, like the VM.
#
# Unverified / needs a live pull-test before enabling (see rollout notes in the
# module header of hosts/odin or docs):
#   1. image name/tag  : "itzcrazykns1337/vane:latest" — the 2026 rebrand of
#      ItzCrazyKns/Perplexica is claimed to be a single container bundling the
#      UI + API + a private SearXNG (no separate searxng service needed).
#   2. web port        : claimed 3000 (verify against the real image EXPOSE).
#   3. ollama reach    : host ollama binds 0.0.0.0:11434; reached from the
#      container via host.containers.internal (rootless-podman/pasta default).
#
# One-time (admin, not per-end-user): the first launch shows a Setup Wizard to
# pick the Ollama provider + model. There is NO built-in multi-user login — this
# module is intentionally LAN-only and unauthenticated (matches the chosen
# deployment: trusted home network behind adguard/unbound).
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.vane;
in
{
  options.services.vane = {
    enable = lib.mkEnableOption "Vane (Perplexica) self-hosted AI search on the local ollama";
    image = lib.mkOption {
      type = lib.types.str;
      # Fully-qualified: no unqualified-search registries are configured on
      # odin (see /etc/containers/registries.conf), so a bare short-name fails
      # with "did not resolve to an alias". Same docker.io/ prefix the dockur
      # windows image uses on this host.
      default = "docker.io/itzcrazykns1337/vane:latest";
      description = "OCI image (single container: UI + API + private SearXNG).";
    };
    port = lib.mkOption {
      type = lib.types.port;
      # 3000 is taken by AdGuard Home (bound 127.0.0.1) on this host, so Vane
      # listens on a free port. Published on all interfaces for LAN access.
      default = 3005;
      description = "Host port to publish the Vane web UI on (all interfaces).";
    };
    containerPort = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Port the web UI listens on inside the container.";
    };
    ollamaUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://host.containers.internal:11434";
      description = "Base URL of the local ollama service as seen from the container.";
    };
    embeddingModel = lib.mkOption {
      type = lib.types.str;
      default = "qwen3-embedding:latest";
      description = "Local ollama embedding model used for retrieval modes.";
    };
  };

  config = lib.mkIf (cfg.enable && config.lib.neg.enabled "llm") {
    # Vane as a rootless podman container in the neg user session.
    systemd.user.services.vane = {
      description = "Vane (Perplexica) self-hosted AI search engine";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        # podman run stays in the foreground as long as the container lives;
        # on exit systemd restarts and --replace re-creates the named container.
        ExecStart = lib.concatStringsSep " " [
          "${lib.getExe pkgs.podman} run"
          "--name vane --replace --rm"
          "-p ${toString cfg.port}:${toString cfg.containerPort}"
          "-e OLLAMA_BASE_URL=${cfg.ollamaUrl}"
          "-e OLLAMA_EMBEDDING_MODEL=${cfg.embeddingModel}"
          "-v vane-data:/home/vane/data"
          cfg.image
        ];
        Restart = "on-failure";
        RestartSec = 10;
        TimeoutStartSec = 300;
      };
    };

    # Open the published port so LAN devices (household) can reach the UI.
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };

}
