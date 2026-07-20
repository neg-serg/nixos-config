{ pkgs, lib, ... }:
{
  environment.systemPackages = [
    pkgs.hyprland-qt-support # Qt integration helpers for Hyprland
    pkgs.hyprland-qtutils # Qt extras (hyprland-qt-helper)
    pkgs.kdePackages.qt5compat # Qt6 QtQuick bridge
    pkgs.kdePackages.qtpositioning # Qt positioning (sensors)
    pkgs.kdePackages.qtwayland # Qt Wayland plugin
    pkgs.kdePackages.syntax-highlighting # KSyntaxHighlighting for QML
    pkgs.qt6.qtimageformats # supplemental Qt6 image formats
    pkgs.qt6.qtsvg # supplemental Qt6 SVG support

    # Wrapped kvantummanager with SVG plugin path for theme previews
    (pkgs.writeShellApplication {
      name = "kvantummanager";
      runtimeInputs = [ pkgs.kdePackages.qtstyleplugin-kvantum ];
      text = ''
        export QT_PLUGIN_PATH="${pkgs.qt6.qtsvg}/${pkgs.qt6.qtbase.qtPluginPrefix}${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
        exec ${lib.getExe' pkgs.kdePackages.qtstyleplugin-kvantum "kvantummanager"}
      '';
    })
  ];
}
