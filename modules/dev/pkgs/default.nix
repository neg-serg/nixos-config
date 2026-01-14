{
  lib,
  pkgs,
  ...
}:
{
  environment.systemPackages = lib.unique ([
    # Former base system dev helpers
    pkgs.just # command runner for project tasks
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

    # Static analysis and linters
    pkgs.flawfinder # C/C++ security scanner
    pkgs.shellcheck # shell linter
    pkgs.codeql # GitHub CodeQL CLI for queries

    # Code counting/reporting utilities
    pkgs.cloc # count lines of code
    pkgs.scc # parallel code counter
    pkgs.tokei # fast code statistics

    # Radicle tooling
    pkgs.radicle-node # Radicle node/server
    pkgs.radicle-explorer # Radicle web explorer

    # General runtimes & helpers
    pkgs.deheader # trim redundant C/C++ includes

  ]);
}
