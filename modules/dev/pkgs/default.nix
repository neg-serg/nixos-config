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
