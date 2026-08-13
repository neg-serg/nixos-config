{
  pkgs,
  ...
}:
# Lightweight devshell for 'just lint' / .githooks/pre-commit.
# No preCommit shellHook here (unlike base.nix) so running the lint suite
# never touches .git/hooks. Keep the tool list in sync with base.nix.
pkgs.mkShell {
  packages = [
    pkgs.just # command runner
    pkgs.jq # json processor
    # Nix linters/formatters
    pkgs.nixfmt # nix formatter
    pkgs.deadnix # unused code detector
    pkgs.statix # nix antipattern linter
    # Python
    pkgs.black # Python code formatter
    pkgs.ruff # Python linter
    pkgs.mypy # Optional static typing for Python
    pkgs.python3 # for YAML/TOML syntax checks
    pkgs.python3Packages.pyyaml # YAML syntax check
    # Lua
    pkgs.stylua # Lua formatter
    # QML
    pkgs.selene # Lua linter
    pkgs.qt6.qtdeclarative # qmlformat: QML syntax checker
    # Shell
    pkgs.shellcheck # shell linter
    # Rust
    pkgs.rustfmt # rust formatting check
    # TOML
    pkgs.taplo # TOML formatter/linter
  ];
}
