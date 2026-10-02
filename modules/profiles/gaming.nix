{ lib, config, ... }:
lib.mkIf (builtins.elem "gaming" (config.features.profiles or [ ])) {
  features = {
    optimization.enable = lib.mkDefault true;
    gui.hdr.enable = lib.mkDefault true;
  };
}
