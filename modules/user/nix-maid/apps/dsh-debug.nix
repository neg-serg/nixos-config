{
  pkgs,
  ...
}:
{
  # js-debug-adapter binary for JS/TS debugging, used by the TUI's dsh-debug
  # plugin. The web-profile caretaker was removed in 2026-09; the TUI profile
  # seeds the plugin itself (dsh-tui-ru.nix).
  environment.systemPackages = [
    pkgs.vscode-js-debug # DAP JS/TS debugger adapter for dsh-debug
  ];
}
