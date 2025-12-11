{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
  mkIf config.features.gui.enable {
    home.packages = with pkgs; [
      wayvnc # remote desktop server for Wayland
      wl-clipboard # command-line copy/paste utilities for Wayland
      wl-ocr # wayland OCR script
    ];
  }
