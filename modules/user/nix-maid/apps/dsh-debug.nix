{
  pkgs,
  config,
  ...
}:
let
  # The DAP adapter is spawned only while a JS/TS session is being debugged,
  # so its 32.7 MiB exclusive closure is built on first use.
  onDemand = config.lib.neg.onDemand pkgs;
in
{
  # js-debug-adapter binary for JS/TS debugging, used by the TUI's dsh-debug
  # plugin. The web-profile caretaker was removed in 2026-09; the TUI profile
  # seeds the plugin itself (dsh-tui.nix).
  environment.systemPackages = [
    (onDemand {
      name = "js-debug";
      attr = "vscode-js-debug";
    }) # DAP JS/TS debugger adapter for dsh-debug, built on first use
  ];
}
