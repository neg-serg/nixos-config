{
  lib,
  pkgs,
  ...
}:
let
  # Optional packages only available on some nixpkgs revisions.
  optionalIaCTools = lib.optionals (pkgs ? aiac) [ pkgs.aiac ]; # AI infrastructure as code generator

in
{
  environment.systemPackages = lib.unique (
    [
      # Former base system dev helpers
      pkgs.just # command runner for project tasks
      pkgs.bpftrace # trace events via eBPF
      pkgs.cutter # Rizin-powered reverse engineering UI
      pkgs.foremost # recover files from raw disk data
      pkgs.freeze # render source files to images
      pkgs.hexyl # hexdump viewer
      pkgs.hyperfine # benchmarking tool
      pkgs.license-generator # CLI license boilerplates
      pkgs.lzbench # compression benchmark
      pkgs.pkgconf # pkg-config wrapper
      pkgs.plow # HTTP benchmarking tool
      pkgs.radare2 # command-line disassembler
      pkgs.strace # trace syscalls
      pkgs.zee # terminal text editor (Rust)

      # Formatters and beautifiers
      pkgs.shfmt # shell formatter
      pkgs.black # Python formatter
      pkgs.stylua # Lua formatter

      # Static analysis and linters
      pkgs.flawfinder # C/C++ security scanner
      pkgs.ruff # Python linter
      pkgs.shellcheck # shell linter
      pkgs.mypy # Python type checker
      pkgs.codeql # GitHub CodeQL CLI for queries

      # Code counting/reporting utilities
      pkgs.cloc # count lines of code
      pkgs.scc # parallel code counter
      pkgs.tokei # fast code statistics

      # Radicle tooling
      pkgs.radicle-node # Radicle node/server
      pkgs.radicle-explorer # Radicle web explorer

      # General runtimes & helpers
      pkgs.jdk21 # Java Development Kit
      pkgs.gradle # Build automation tool for Java/Kotlin/Groovy
      pkgs.nodejs_24 # Node.js runtime tooling
      pkgs.vlang # V programming language compiler
      pkgs.deheader # trim redundant C/C++ includes

    ]
    ++ optionalIaCTools
  );
}
