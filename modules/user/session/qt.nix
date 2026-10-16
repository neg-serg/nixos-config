{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.hyprland-qt-support # Qt integration helpers for Hyprland
    pkgs.hyprqt6engine # Qt6 platform theme/styling fed by the Hyprland config
    pkgs.kdePackages.qtpositioning # Qt positioning (sensors)
    pkgs.kdePackages.qtwayland # Qt Wayland plugin
    pkgs.kdePackages.syntax-highlighting # KSyntaxHighlighting for QML
    pkgs.qt6.qtimageformats # supplemental Qt6 image formats
    pkgs.qt6.qtsvg # supplemental Qt6 SVG support
  ];
}
