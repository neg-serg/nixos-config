{
  lib,
  pkgs,
  config,
  rsmetrxProvider ? null,
  ...
}:
with lib;
  mkIf (config.features.gui.enable && (config.features.gui.qt.enable or false) && (! (config.features.devSpeed.enable or false))) {
    home.packages = config.lib.neg.pkgsList [
      pkgs.cantarell-fonts # GNOME Cantarell fonts
      pkgs.cava # console audio visualizer
      (
        if rsmetrxProvider != null
        then (rsmetrxProvider pkgs)
        else pkgs.emptyFile
      ) # metrics/telemetry helper
      pkgs.kdePackages.kdialog # simple Qt dialog helper
      pkgs.kdePackages.qt5compat # Qt5Compat modules in Qt6
      pkgs.kdePackages.qtdeclarative # Qt 6 QML
      pkgs.kdePackages.qtimageformats # extra image formats
      pkgs.kdePackages.qtmultimedia # multimedia QML/Qt
      pkgs.kdePackages.qtpositioning # positioning QML/Qt
      pkgs.kdePackages.qtquicktimeline # timeline QML
      pkgs.kdePackages.qtsensors # sensors QML/Qt
      pkgs.kdePackages.qtsvg # SVG support
      pkgs.kdePackages.qttools # Qt tooling
      pkgs.kdePackages.qttranslations # Qt translations
      pkgs.kdePackages.qtvirtualkeyboard # on-screen keyboard
      pkgs.kdePackages.qtwayland # Wayland platform plugin
      pkgs.kdePackages.syntax-highlighting # KSyntaxHighlighting
      pkgs.libxml2 # xmllint for SVG validation
      pkgs.librsvg # rsvg-convert for SVG raster validation
      pkgs.material-symbols # Material Symbols font
      pkgs.networkmanager # nmcli and helpers
      pkgs.qt6.qtimageformats # extra image formats (Qt6)
      pkgs.qt6.qtsvg # SVG support (Qt6)
    ];
  }
