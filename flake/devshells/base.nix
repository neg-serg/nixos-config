{
  pkgs,
  ...
}:
pkgs.mkShell {
  packages = [
    pkgs.valgrind # Tool for debugging and profiling
    pkgs.nixfmt # nix formatter
    pkgs.deadnix # unused code detector
    pkgs.statix # nix antipattern linter
    pkgs.nil # nix language server
    pkgs.just # command runner
    pkgs.jq # json processor
    pkgs.perf # Linux profiling with perf_events (top-level alias; tracks kernel version)
    pkgs.hyperfine # command-line benchmarking tool
    # Linters/Formatters required by 'just lint' (moved from system pkgs)
    pkgs.black # Python code formatter
    pkgs.ruff # Extremely fast Python linter and code formatter
    pkgs.mypy # Optional static typing for Python
    pkgs.stylua # Opinionated Lua code formatter
    pkgs.luajit # Lua syntax checker
    pkgs.qt6.qtdeclarative # qmlformat: QML syntax checker for 'just lint'
  ];
}
