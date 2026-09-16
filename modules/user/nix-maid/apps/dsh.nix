{
  config,
  pkgs,
  ...
}:
let
  inherit (config.lib.neg) homeDir;
  # Wrap dsh so it loads DEEPSEEK_API_KEY from the sops secret itself, rather
  # than relying on shell init — works even from a terminal opened before the
  # secret was wired (a shell only sources .zshenv at startup).
  #
  # DSH_TUI_STATUSLINE is the user-script status line. The TUI bundle ships the
  # runner but never instantiates it (see docs/howto/dsh-statusline.md), so
  # dsh-tui-ru.nix patches it in and reads the command from this variable.
  # Overridable, and skipped when the helper is not installed.
  dshWrapped = pkgs.writeShellScriptBin "dsh" ''
    export DEEPSEEK_API_KEY="''${DEEPSEEK_API_KEY:-$(cat /run/secrets/deepseek-api 2>/dev/null)}"
    if [ -x "${homeDir}/.local/bin/dsh-statusline" ]; then
      export DSH_TUI_STATUSLINE="''${DSH_TUI_STATUSLINE:-${homeDir}/.local/bin/dsh-statusline}"
    fi
    exec ${pkgs.neg.dsh}/bin/dsh "$@"
  '';

  # Martty trial launcher: the trial profile (see dsh-martty.nix) behind the
  # same wrapper, so it inherits the DEEPSEEK_API_KEY bootstrap. The Tianshu
  # status-line variable is dropped — Martty drives its own composer/status UI.
  dshMartty = pkgs.writeShellScriptBin "dsh-martty" ''
    exec ${dshWrapped}/bin/dsh --profile martty "$@"
  '';
in
{
  # DeepSeek Harness (dsh) — agent harness, everything is a plugin. Terminal
  # first on this host: the web GUI service (port 3080), the watchdog and the
  # port-3080 firewall opening were removed in 2026-09, so `dsh web` runs on
  # demand only and stays loopback-bound. The TUI lives in dsh-tui-ru.nix;
  # nothing here starts a daemon.

  # Phone access (dsh-pocket, installed in the `web` profile). While `dsh web`
  # runs, the plugin's in-process bridge listens on 0.0.0.0:3081 and proxies to
  # the loopback web app — only the bridge is reachable from the LAN, and every
  # non-loopback request must pass the plugin's own 8-char PIN, so this rule is
  # the second gate rather than the only one.
  #
  # Scoped to the uplink the phone shares (Wi-Fi clients of the 192.168.2.x
  # router arrive here), the same way net-health opens 2586.
  networking.firewall.interfaces.net1.allowedTCPPorts = [
    3081 # dsh-pocket phone bridge (proxies 127.0.0.1:3080, PIN-gated)
  ];

  # Install the dsh CLI into the environment (PATH).
  environment.systemPackages = [
    dshWrapped # DeepSeek Harness agent CLI (dsh) — wrapped to load the DeepSeek API key
    dshMartty # `dsh-martty` — launches the trial martty profile (see dsh-martty.nix)
    pkgs.pnpm # pnpm package manager (used by `dsh plugin --profile <name> add`)
    pkgs.gnumake # make — required by node-gyp when pnpm builds native deps (node-pty) in a profile
  ];
}
