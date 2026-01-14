{
  lib,
  pkgs,
  ...
}:
{
  environment.systemPackages = lib.unique ([
    # Former base system dev helpers
    pkgs.freeze # render source files to images
    pkgs.hexyl # hexdump viewer
    pkgs.hyperfine # benchmarking tool
    pkgs.just # command runner for project tasks
    pkgs.license-generator # CLI license boilerplates
    pkgs.lzbench # compression benchmark
    pkgs.pkgconf # pkg-config wrapper
    pkgs.plow # HTTP benchmarking tool
    pkgs.strace # trace syscalls
    pkgs.zee # terminal text editor (Rust)

    # Formatters and beautifiers
    pkgs.shfmt # shell formatter

    # Static analysis and linters
    pkgs.shellcheck # shell linter

    # Code counting/reporting utilities
    pkgs.cloc # count lines of code
    pkgs.scc # parallel code counter
    pkgs.tokei # fast code statistics

    # General runtimes & helpers
    pkgs.deheader # trim redundant C/C++ includes

  ]);
}
