{
  lib,
  pkgs,
  ...
}:
{
  environment.systemPackages = lib.unique ([
    pkgs.freeze # render source files to images
    pkgs.hexyl # hexdump viewer
    pkgs.hyperfine # benchmarking tool
    pkgs.just # command runner for project tasks
    pkgs.license-generator # CLI license boilerplates
    pkgs.pkgconf # pkg-config wrapper
    pkgs.plow # HTTP benchmarking tool
    pkgs.strace # trace syscalls
    pkgs.zee # terminal text editor (Rust)
    pkgs.shfmt # shell formatter
    pkgs.shellcheck # shell linter
    pkgs.scc # parallel code counter
    pkgs.deheader # trim redundant C/C++ includes
  ]);
}
