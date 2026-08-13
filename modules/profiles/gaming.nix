{ lib, config, ... }:
with lib;
mkIf (builtins.elem "gaming" (config.features.profiles or [ ])) {
  features = {
    optimization.enable = mkDefault true;
    gui.hdr.enable = mkDefault true;
  };
}
