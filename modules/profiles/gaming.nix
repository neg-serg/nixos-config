{ lib, config, ... }:
with lib;
mkIf (builtins.elem "gaming" (config.features.profiles or [ ])) {
  features = {
    games.enable = mkDefault true;
    optimization.enable = mkDefault true;
    gui.hdr.enable = mkDefault true;
    apps.guiAppsFull.enable = mkDefault true;
  };
}
