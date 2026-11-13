##
# Module: user/nix-maid/sys/user-services/crawl4ai
# Purpose: run the Crawl4AI server locally, so pages can be turned into
# LLM-ready Markdown over REST (POST /md, /crawl, /screenshot, /pdf, /execute_js) or MCP
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
# Why a split proxy in front of the crawler: rutracker.org is throttled to
# ~0.5 kB/s for this IP (Cloudflare), while the host's SOCKS proxy
# (sing-box-proxy, 127.0.0.1:10808) loads it at full speed. Most other sites
# are faster direct, and some (lenta.ru) do not work through the proxy exit at
# all. crawl4ai's egress pinning proxy accepts a single upstream for every
# browser connection (CRAWL4AI_UPSTREAM_PROXY), and the browser connects to
# the pinned IP, so the upstream never sees a hostname. The router below
# (`crawl4ai-split-proxy`, sing-box) sniffs the TLS SNI and sends only
# rutracker domains through the SOCKS proxy; everything else stays direct.
# Without it the crawler either cannot load rutracker (direct: navigation
# times out after 60 s) or loses lenta.ru (global upstream).
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

  # The router listens on 0.0.0.0 because pasta maps host.containers.internal
  # to the host, not to the host's 127.0.0.1. The NixOS firewall keeps the port
  # off the LAN; the router only serves this crawler and only sends rutracker
  # through the SOCKS proxy.
  splitProxyPort = 18080;

  # Hosts whose traffic must take the SOCKS path: rutracker.org plus the asset
  # and redirect domains its pages use.
  rutrackerDomains = [
    "rutracker.org"
    "rutracker.cc"
    "rutracker.net"
    "rutracker.nl"
    "t-ru.org"
  ];

  # `action = "sniff"` is what makes this work: the browser CONNECTs to the
  # pinned IP, so the SNI from the ClientHello is the only domain information
  # the router gets.
  splitProxyConfig = pkgs.writeText "crawl4ai-split-proxy.json" (
    builtins.toJSON {
      log.level = "warn";
      inbounds = [
        {
          type = "http";
          tag = "in";
          listen = "0.0.0.0";
          listen_port = splitProxyPort;
        }
      ];
      outbounds = [
        {
          type = "socks";
          tag = "up";
          server = "127.0.0.1";
          server_port = 10808;
        }
        {
          type = "direct";
          tag = "direct";
        }
      ];
      route = {
        rules = [
          { action = "sniff"; }
          {
            domain_suffix = rutrackerDomains;
            outbound = "up";
          }
          {
            ip_is_private = true;
            outbound = "direct";
          }
        ];
        final = "direct";
      };
    }
  );

  # A malformed router config must fail the rebuild, not every crawl.
  splitProxyChecked = pkgs.runCommand "crawl4ai-split-proxy-checked" { } ''
    ${lib.getExe pkgs.sing-box} check -c ${splitProxyConfig}
    install -m 0644 ${splitProxyConfig} $out
  '';

  # Reads the token in the user's session, never stores it. The container gets
  # it through podman's own environment (`-e NAME` copies the value), so the
  # secret is absent from the podman argv that `ps` shows.
  server = pkgs.writeShellApplication {
    name = "crawl4ai-server";
    runtimeInputs = [
      pkgs.gopass # token lookup from the password store
      pkgs.gnupg # gpg-agent that gopass shells out to
      config.virtualisation.podman.package # rootless container runtime
      pkgs.coreutils # standard utilities for the wrapper's shell
    ];
    text = ''
      set -euo pipefail

      CRAWL4AI_API_TOKEN="$(gopass show -o ${tokenEntry})"
      export CRAWL4AI_API_TOKEN

      # Egress routing for the browser: name the split router, not the SOCKS
      # proxy. The router decides per SNI; the value is exported so `-e NAME`
      # copies it into the container without putting it into podman's argv.
      CRAWL4AI_UPSTREAM_PROXY="http://host.containers.internal:${toString splitProxyPort}"
      export CRAWL4AI_UPSTREAM_PROXY

      # /execute_js answers 403 unless this flag is set; it also unlocks the
      # js_code step in /crawl (run page JS before extraction).
      CRAWL4AI_EXECUTE_JS_ENABLED=true
      export CRAWL4AI_EXECUTE_JS_ENABLED

      # --shm-size=1g: Chromium needs more than the 64M default for tabs.
      # --rm: a crash leaves no stopped container behind; systemd restarts the
      # unit and podman creates a fresh one.
      #
      # --http-proxy=false: podman copies the host's http(s)_proxy into the
      # container, where 127.0.0.1 is the container's own loopback and every
      # fetch dies with ERR_TUNNEL_CONNECTION_FAILED. The explicit upstream
      # (CRAWL4AI_UPSTREAM_PROXY, above) points at the split router instead;
      # the routing decision for rutracker lives there.
      exec podman run --rm --name crawl4ai \
        --shm-size=1g \
        --http-proxy=false \
        -p 127.0.0.1:11235:11235 \
        -e CRAWL4AI_API_TOKEN \
        -e CRAWL4AI_UPSTREAM_PROXY \
        -e CRAWL4AI_EXECUTE_JS_ENABLED \
        ${image}
    '';
  };

  cli = pkgs.writeShellApplication {
    name = "crawl4ai";
    runtimeInputs = [
      pkgs.curl # REST calls to the local server
      pkgs.gopass # token for authenticated endpoints
      pkgs.jq # /md answers with a JSON body
      config.virtualisation.podman.package # image pull
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
          echo "split proxy: $(systemctl --user is-active crawl4ai-split-proxy 2>/dev/null || true)"
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

  # Router between the crawler's egress proxy and the network: rutracker goes
  # through sing-box-proxy, everything else direct. Started with the session
  # because the crawler is on demand and needs an upstream at every fetch.
  systemd.user.services.crawl4ai-split-proxy = systemdUser.mkUserService {
    presets = [
      "defaultWanted"
      "restartOnFailure"
    ];
    description = "Crawl4AI split proxy: rutracker via sing-box SOCKS, everything else direct";
    after = [ "sing-box-proxy.service" ];
    wants = [ "sing-box-proxy.service" ];
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.sing-box} run -c ${splitProxyChecked}";
      RestartSec = 5;
      # Both halves of the crawler have no interactive peak; start them on
      # demand (`crawl4ai up`), so the background class is the right home.
      Slice = "background.slice";
    };
  };

  systemd.user.services.crawl4ai-server = systemdUser.mkUserService {
    presets = [ "restartOnFailure" ];
    description = "Crawl4AI server: LLM-ready Markdown over REST on 127.0.0.1:11235";
    after = [ "crawl4ai-split-proxy.service" ];
    wants = [ "crawl4ai-split-proxy.service" ];
    serviceConfig = {
      ExecStart = getExe server;
      RestartSec = 10;
      Slice = "background.slice";
    };
  };
}
