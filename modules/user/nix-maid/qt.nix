{
  pkgs,
  config,
  lib,
  ...
}: let
  qtEnabled = config.features.gui.qt.enable or false;
in {
  config = lib.mkIf qtEnabled {
    environment.systemPackages = [
      # Qt 5
      pkgs.libsForQt5.qt5.qtsvg # SVG support for Qt 5
      pkgs.libsForQt5.qt5.qtwayland # Wayland support for Qt 5
      pkgs.libsForQt5.qt5ct # Qt 5 configuration tool
      pkgs.libsForQt5.qtstyleplugin-kvantum # SVG-based theme engine for Qt 5

      # Qt 6
      pkgs.kdePackages.qt6ct # Qt 6 configuration tool
      pkgs.kdePackages.qtwayland # Wayland support for Qt 6
      pkgs.kdePackages.svgpart # SVG part for KDE
    ];

    environment.sessionVariables = {
      QT_QPA_PLATFORMTHEME = "qt6ct"; # Use qt6ct to configure Qt6 (and Qt5 if configured to use it)
    };

    environment.variables = {
      QT_STYLE_OVERRIDE = "kvantum"; # Force kvantum style if possible
    };

    # Restore Kvantum config managed by HM
    users.users.neg.maid.file.home = {
      ".config/Kvantum/kvantum.kvconfig".text = ''
        [General]
        theme=KvantumAlt
      '';

      ".config/qt6ct/qt6ct.conf".text = ''
        [Appearance]
        standard_dialogs=xdgdesktopportal
      '';

      ".config/qt5ct/qt5ct.conf".text = ''
        [Appearance]
        standard_dialogs=xdgdesktopportal
      '';
    };
  };
}
