{
  pkgs,
  config,
  ...
}:
let
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") {
    inherit pkgs;
    nix = config.nix.package;
  };
in
{
  # ast-grep binary for the structural search tool used by the TUI's
  # dsh-ast-grep plugin. The web-profile caretaker was removed in 2026-09; the
  # TUI profile seeds the plugin itself (dsh-tui.nix).
  environment.systemPackages = [
    (onDemand {
      name = "ast-grep";
      attr = "ast-grep";
    }) # AST structural search/rewrite for dsh-ast-grep, built on first use
  ];
}
