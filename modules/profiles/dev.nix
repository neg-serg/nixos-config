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
      pkgs.formatters = mkDefault true;
      pkgs.codecount = mkDefault true;
      pkgs.analyzers = mkDefault true;
      pkgs.iac = mkDefault true;
      pkgs.radicle = mkDefault true;
      pkgs.runtime = mkDefault true;
      pkgs.misc = mkDefault true;
    };
    hack.enable = mkDefault true;
  };
}
