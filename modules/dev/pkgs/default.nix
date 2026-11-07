{
  lib,
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
  environment.systemPackages = lib.unique ([
    pkgs.hyperfine # benchmarking tool
    pkgs.just # command runner for project tasks
    pkgs.pkgconf # pkg-config wrapper
    (onDemand {
      name = "scc";
      attr = "scc";
    }) # parallel code counter, built on first use
    pkgs.shellcheck # shell linter
    pkgs.shfmt # shell formatter
    pkgs.strace # trace syscalls
    (onDemand {
      name = "strace-tui";
      attr = "strace-tui";
    }) # syscall-trace explorer for strace output, built on first run
    pkgs.uv # Python package manager (uvx for MCP servers like qdrant, blender, wireshark, arxiv, serena)
  ]);

  # oh-my-openagent MCP plugin hardcodes /usr/bin/uvx for Python-based MCP servers
  # (qdrant, blender, wireshark, arxiv, serena). NixOS installs uvx under
  # /run/current-system/sw/bin, so we bridge the gap with a symlink.
  system.activationScripts.uvxCompatSymlink = ''
    mkdir -p /usr/bin
    ln -sfn ${lib.getExe' pkgs.uv "uvx"} /usr/bin/uvx
  '';
}
