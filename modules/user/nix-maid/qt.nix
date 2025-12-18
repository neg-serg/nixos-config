{
  pkgs,
  config,
  lib,
  ...
}: let
  qtEnabled = config.features.gui.qt.enable or false;
in {
  config = lib.mkIf qtEnabled {
    environment.systemPackages = with pkgs; [
      # Qt 5
      libsForQt5.qt5.qtsvg
      libsForQt5.qt5.qtwayland
      libsForQt5.qt5ct
      libsForQt5.qtstyleplugin-kvantum

      # Qt 6
      kdePackages.qt6ct
      kdePackages.qtwayland
      kdePackages.svgpart
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
