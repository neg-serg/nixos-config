{
  pkgs,
  config,
  lib,
  ...
}: let
  qtEnabled = config.features.gui.qt.enable or false;
in {
  config = lib.mkIf qtEnabled {
    qt = {
      enable = true;
      # platformTheme.name = "qt6ct";
      # style.name = "kvantum";
    };

    home.packages = with pkgs; [
      # -- Qt5 --
      libsForQt5.qt5.qtsvg # SVG module for Qt5
      libsForQt5.qt5.qtwayland # Qt5 Wayland backend
      libsForQt5.qt5ct # Qt5 configuration tool
      libsForQt5.qtstyleplugin-kvantum # SVG-based theme engine for Qt5

      # -- Qt6 --
      kdePackages.qt6ct # Qt6 configuration tool
      kdePackages.qtwayland # Qt6 Wayland backend
      kdePackages.svgpart # SVG viewer component for Qt6
    ];
  };
}
