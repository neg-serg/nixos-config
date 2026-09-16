{
  pkgs,
  ...
}:
{
  # ast-grep binary for the structural search tool used by the TUI's
  # dsh-ast-grep plugin. The web-profile caretaker was removed in 2026-09; the
  # TUI profile seeds the plugin itself (dsh-tui.nix).
  environment.systemPackages = [
    pkgs.ast-grep # AST structural search/rewrite for dsh-ast-grep
  ];
}
