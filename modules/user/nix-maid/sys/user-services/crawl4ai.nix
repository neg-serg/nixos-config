##
# Module: user/nix-maid/sys/user-services/crawl4ai
# Purpose: run the Crawl4AI server locally, so pages can be turned into
# LLM-ready Markdown over REST (POST /md, /crawl, /screenshot, /pdf) or MCP
# (/mcp/sse) without handing the pages to a hosted service. The server is the
# official container image, rootless podman, bound to 127.0.0.1:11235.
#
# Why a user unit: the bearer token lives in gopass (`api/crawl4ai`) and only
# the user's gpg-agent can decrypt it. A rootful container would need a
# root-owned plaintext copy, and baking it into the unit would put it in
# /nix/store (world-readable). The unit therefore runs as the user and reads
# the token at start.
#
# Why no defaultWanted: a user unit starts with the user manager at login,
# before gpg-agent is unlocked, and user units do not inherit DISPLAY — a
# locked agent would block on a pinentry nobody can answer and the unit would
# restart-loop. Start it on demand with `crawl4ai up` from a session where the
# token can be unlocked.
#
# The image tag is pinned to the library release. First start pulls ~2–3 GB
# (`crawl4ai pull` shows progress); afterwards the container starts in seconds.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib)
    getExe
    mkIf
    ;

  enabled = config.lib.neg.enabled "dev.ai.crawl4ai";
  systemdUser = config.lib.neg.systemdUser;

  # Secret naming follows the store's api/<service> convention.
  tokenEntry = "api/crawl4ai";
  image = "unclecode/crawl4ai:0.9.5";

  # Reads the token in the user's session, never stores it. The container gets
  # it through podman's own environment (`-e NAME` copies the value), so the
  # secret is absent from the podman argv that `ps` shows.
  server = pkgs.writeShellApplication {
    name = "crawl4ai-server";
    runtimeInputs = [
      pkgs.gopass # token lookup from the password store
      pkgs.gnupg # gpg-agent that gopass shells out to
      pkgs.podman # rootless container runtime
      pkgs.coreutils # standard utilities for the wrapper's shell
    ];
    text = ''
      set -euo pipefail

      CRAWL4AI_API_TOKEN="$(gopass show -o ${tokenEntry})"
      export CRAWL4AI_API_TOKEN

      # --shm-size=1g: Chromium needs more than the 64M default for tabs.
      # --rm: a crash leaves no stopped container behind; systemd restarts the
      # unit and podman creates a fresh one.
      #
      # --http-proxy=false: podman copies the host's http(s)_proxy into the
      # container, where 127.0.0.1 is the container's own loopback and every
      # fetch dies with ERR_TUNNEL_CONNECTION_FAILED. The host reaches the web
      # directly (DPI bypass lives in zapret2), so the container goes direct
      # too. A target that needs the SOCKS/HTTP proxy has to be routed through
      # host.containers.internal explicitly — not enabled here on purpose.
      exec podman run --rm --name crawl4ai \
        --shm-size=1g \
        --http-proxy=false \
        -p 127.0.0.1:11235:11235 \
        -e CRAWL4AI_API_TOKEN \
        ${image}
    '';
  };

  cli = pkgs.writeShellApplication {
    name = "crawl4ai";
    runtimeInputs = [
      pkgs.curl # REST calls to the local server
      pkgs.gopass # token for authenticated endpoints
      pkgs.jq # /md answers with a JSON body
      pkgs.podman # image pull
      pkgs.systemd # systemctl/journalctl --user for the unit lifecycle
      pkgs.coreutils # standard utilities for the wrapper's shell
    ];
    text = ''
      set -euo pipefail

      base="http://127.0.0.1:11235"
      unit="crawl4ai-server"

      usage() {
        cat <<'EOF'
      usage: crawl4ai <command> [args]

        up          start the local server (user unit, podman)
        down        stop it
        pull        pull the pinned image (first run only, ~2–3 GB)
        status      unit state + GET /health
        logs        follow the unit journal
        token       print the API token (gopass api/crawl4ai)
        md URL      POST /md and print the Markdown
      EOF
      }

      case "''${1:-}" in
        up)
          systemctl --user start "$unit"
          for _ in {1..40}; do
            if curl -fsS "$base/health" >/dev/null 2>&1; then
              echo "crawl4ai ready on $base (playground: $base/playground)"
              exit 0
            fi
            sleep 1
          done
          echo "unit started, but $base/health is silent — a first-run image" >&2
          echo "pull can take minutes: journalctl --user -u $unit -f" >&2
          exit 1
          ;;
        down)
          systemctl --user stop "$unit"
          ;;
        pull)
          podman pull ${image}
          ;;
        status)
          systemctl --user --no-pager --lines=0 status "$unit" || true
          echo "---"
          curl -fsS "$base/health" || {
            echo "no answer from $base/health" >&2
            exit 1
          }
          echo
          ;;
        logs)
          journalctl --user -u "$unit" -f
          ;;
        token)
          gopass show -o ${tokenEntry}
          ;;
        md)
          [ -n "''${2:-}" ] || {
            echo "usage: crawl4ai md URL" >&2
            exit 2
          }
          curl -fsS -X POST "$base/md" \
            -H "Authorization: Bearer $(gopass show -o ${tokenEntry})" \
            -H "Content-Type: application/json" \
            -d "$(jq -cn --arg url "$2" '{url: $url}')" \
            | jq -r .markdown
          ;;
        *)
          usage
          exit 2
          ;;
      esac
    '';
  };
in
mkIf enabled {
  environment.systemPackages = [
    cli # `crawl4ai` control CLI: up/down/pull/status/logs/token/md
  ];

  systemd.user.services.crawl4ai-server = systemdUser.mkUserService {
    presets = [ "restartOnFailure" ];
    description = "Crawl4AI server: LLM-ready Markdown over REST on 127.0.0.1:11235";
    serviceConfig = {
      ExecStart = getExe server;
      RestartSec = 10;
    };
  };
}
