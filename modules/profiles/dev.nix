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
      pkgs.formatters = mkDefault true; # formatters (alejandra, deadnix, shfmt, etc.)
      pkgs.codecount = mkDefault true; # code metric tools (cloc, gocloc)
      pkgs.analyzers = mkDefault true; # static analyzers
      pkgs.iac = mkDefault true; # IaC tools (terraform, opentofu)
      pkgs.radicle = mkDefault true; # Radicle CLI
      pkgs.runtime = mkDefault true; # language runtimes (go, zig, node, deno, bun)
      pkgs.misc = mkDefault true; # miscellaneous dev tools
    };
    hack.enable = mkDefault true;
  };
}
