{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.hyprland-qt-support # Qt integration helpers for Hyprland
    pkgs.hyprland-qtutils # Qt extras (hyprland-qt-helper)
    pkgs.kdePackages.qt5compat # Qt6 QtQuick bridge
    pkgs.kdePackages.qt6ct # Qt6 configuration utility
    pkgs.kdePackages.qtdeclarative # QtDeclarative (QML runtime)
    pkgs.kdePackages.qtimageformats # extra Qt image formats
    pkgs.kdePackages.qtpositioning # Qt positioning (sensors)
    pkgs.kdePackages.qtquicktimeline # Qt timeline module
    pkgs.kdePackages.qtsensors # Qt sensors module
    pkgs.kdePackages.qtsvg # Qt SVG backend
    pkgs.kdePackages.qttools # Qt utility tooling
    pkgs.kdePackages.qttranslations # Qt translations set
    pkgs.kdePackages.qtvirtualkeyboard # Qt virtual keyboard
    pkgs.kdePackages.qtwayland # Qt Wayland plugin
    pkgs.kdePackages.syntax-highlighting # KSyntaxHighlighting for QML
    pkgs.qt6.qtimageformats # supplemental Qt6 image formats
    pkgs.qt6.qtsvg # supplemental Qt6 SVG support
  ];
}
