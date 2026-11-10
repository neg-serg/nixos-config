{
  pkgs,
  config,
  ...
}:
let
  onDemand = config.lib.neg.onDemand pkgs;
  # Wrap dsh so it loads DEEPSEEK_API_KEY from the sops secret itself, rather
  # than relying on shell init — works even from a terminal opened before the
  # secret was wired (a shell only sources .zshenv at startup).
  #
  # The wrapper also arms the free-tier fallbacks declared in llmRows
  # (dsh-terminal-plugins.nix) and smoke-tested by `free-llm-check`:
  #   * ~/.config/dsh/free-llm.env carries GEMINI_API_KEY
  #     (KEY=VALUE, mode 0600, outside the repo). The check script creates the
  #     template on first run.
  #   * Gemini refuses direct connections from this region, so
  #     NODE_USE_ENV_PROXY makes Node's fetch honour the local sing-box HTTP
  #     inbound. NO_PROXY keeps loopback (llama-swap) and the primary DeepSeek
  #     route on a direct path: a dead proxy must not take the daily driver
  #     down with it.
  #   * POLLINATIONS_API_KEY is a dummy credential — the anonymous route needs
  #     no key, the adapter only needs the variable set.
  dshWrapped = pkgs.writeShellScriptBin "dsh" ''
    export DEEPSEEK_API_KEY="''${DEEPSEEK_API_KEY:-$(cat /run/secrets/deepseek-api 2>/dev/null)}"
    if [ -r "$HOME/.config/dsh/free-llm.env" ]; then
      set -a
      . "$HOME/.config/dsh/free-llm.env"
      set +a
    fi
    export NODE_USE_ENV_PROXY=1
    # HTTPS only: plain-http URLs stay direct, so LAN services reached from a
    # session's bash tool do not suddenly depend on the proxy being up.
    export HTTPS_PROXY="''${HTTPS_PROXY:-http://127.0.0.1:10812}"
    export NO_PROXY="''${NO_PROXY:-127.0.0.1,localhost,::1,api.deepseek.com}"
    export POLLINATIONS_API_KEY="''${POLLINATIONS_API_KEY:-anonymous}"
    # XDG home (see dsh-xdg-migrate.sh). Until the one-time migration has moved
    # ~/.dsh, DSH_HOME stays unset and dsh keeps its own default; afterwards the
    # wrapper pins the XDG location explicitly.
    dsh_home="''${XDG_DATA_HOME:-$HOME/.local/share}/dsh"
    [ -e "$dsh_home" ] && export DSH_HOME="$dsh_home"
    exec ${pkgs.neg.dsh}/bin/dsh "$@"
  '';

  # Smoke test for the free routes: one tool-call request per provider, so a
  # route that chat-answers but cannot emit tool calls is reported as failed.
  # Run it after pasting keys into ~/.config/dsh/free-llm.env.
  freeLlmCheck = pkgs.writeShellScriptBin "free-llm-check" (builtins.readFile ./free-llm-check.sh);
in
{
  # DeepSeek Harness (dsh) — agent harness, everything is a plugin. Terminal
  # first on this host: the web GUI service (port 3080), the watchdog and the
  # port-3080 firewall opening were removed in 2026-09, so `dsh web` runs on
  # demand only and stays loopback-bound. The TUI lives in dsh-tui.nix;
  # nothing here starts a daemon.

  # Phone access (dsh-pocket, installed in the `web` profile). While `dsh web`
  # runs, the plugin's in-process bridge listens on 0.0.0.0:3081 and proxies to
  # the loopback web app — only the bridge is reachable from the LAN, and every
  # non-loopback request must pass the plugin's own 8-char PIN, so this rule is
  # the second gate rather than the only one.
  #
  # Scoped to the uplink the phone shares (Wi-Fi clients of the 192.168.0.x
  # router arrive here), the same way net-health opens 2586.
  networking.firewall.interfaces.net1.allowedTCPPorts = [
    3081 # dsh-pocket phone bridge (proxies 127.0.0.1:3080, PIN-gated)
  ];

  # Install the dsh CLI into the environment (PATH).
  environment.systemPackages = [
    dshWrapped # DeepSeek Harness agent CLI (dsh) — wrapped to load the DeepSeek API key
    freeLlmCheck # free-tier LLM route smoke test (tool-call probe per provider)
    (onDemand {
      name = "pnpm";
      attr = "pnpm";
    }) # pnpm for `dsh plugin`, built on first use
    pkgs.gnumake # make — required by node-gyp when pnpm builds native deps (node-pty) in a profile
  ];
}
