{ pkgs, lib, ... }:
let
  optionalRustDebugAdapters = lib.optionals (pkgs ? codelldb) [
    pkgs.codelldb # LLDB-based debug adapter for Rust (DAP)
  ];
in
{
  nativeBuildInputs = [
    pkgs.rustup # manage Rust channels/components
    pkgs.rust-analyzer # Rust LSP (rustaceanvim); lives here, not in system-path
    pkgs.graphviz # dot backend for rustaceanvim crateGraph
    pkgs.bacon # background rust code checker
    pkgs.evcxr # Rust REPL
  ]
  ++ optionalRustDebugAdapters;
}
