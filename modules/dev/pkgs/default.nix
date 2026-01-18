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
    pkgs.scc # parallel code counter
    pkgs.shellcheck # shell linter
    pkgs.shfmt # shell formatter
    pkgs.strace # trace syscalls
  ]);
}
