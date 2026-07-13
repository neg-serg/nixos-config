{ lib, config, ... }:
with lib;
mkIf (builtins.elem "dev" (config.features.profiles or [ ])) {
  features = {
    dev = {
      enable = mkDefault true;
      ai.enable = mkDefault true;
      rust.enable = mkDefault true;
      cpp.enable = mkDefault true;
      haskell.enable = mkDefault true;
      pkgs.formatters = mkDefault true; # enable code formatters (alejandra, shfmt, stylua, treefmt)
      pkgs.codecount = mkDefault true; # enable code counting tools (cloc, gocloc)
      pkgs.analyzers = mkDefault true; # enable static analysis tools (shellcheck, deadnix, statix)
      pkgs.iac = mkDefault true; # enable Infrastructure as Code tools (terraform, opentofu)
      pkgs.radicle = mkDefault true; # enable Radicle peer-to-peer code collaboration
      pkgs.runtime = mkDefault true; # enable language runtimes (go, zig, node, deno, bun, ...)
      pkgs.misc = mkDefault true; # enable misc dev utilities (hxtools, graphviz, htop, ...)
    };
    hack.enable = mkDefault true;
  };
}
