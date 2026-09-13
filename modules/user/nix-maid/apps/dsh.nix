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
in
{
  # DeepSeek Harness (dsh) — agent harness, everything is a plugin. Terminal
  # only on this host: the web GUI (the `web` service on port 3080, the LAN
  # phone proxy, the watchdog and the port-3080 firewall opening) was removed
  # in 2026-09. The TUI lives in dsh-tui-ru.nix; nothing here starts a daemon.

  # Install the dsh CLI into the environment (PATH).
  environment.systemPackages = [
    dshWrapped # DeepSeek Harness agent CLI (dsh) — wrapped to load the DeepSeek API key
    pkgs.pnpm # pnpm package manager (used by `dsh plugin --profile <name> add`)
    pkgs.gnumake # make — required by node-gyp when pnpm builds native deps (node-pty) in a profile
  ];
}
