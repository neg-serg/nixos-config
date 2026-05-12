{
  lib,
  pkgs,
  ...
}:
{
  environment.systemPackages = lib.unique ([
    pkgs.hyperfine # benchmarking tool
    pkgs.just # command runner for project tasks
    pkgs.pkgconf # pkg-config wrapper
    pkgs.scc # parallel code counter
    pkgs.shellcheck # shell linter
    pkgs.shfmt # shell formatter
    pkgs.strace # trace syscalls
  ]);
}
