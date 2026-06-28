{
  pkgs,
  config,
  lib,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  qtEnabled = config.features.gui.qt.enable or false;
in
{
  config = lib.mkIf qtEnabled (
    lib.mkMerge [
      {
        environment.systemPackages = [
          # Qt 6
          pkgs.kdePackages.qt6ct # Qt 6 configuration tool
          pkgs.kdePackages.qtwayland # Wayland support for Qt 6
          pkgs.kdePackages.svgpart # SVG part for KDE
        ];

        environment.sessionVariables = {
          QT_QPA_PLATFORMTHEME = "qt6ct"; # Use qt6ct to configure Qt6 (and Qt5 if configured to use it)
          QT_XDG_DESKTOP_PORTAL = "1"; # Force Qt applications to use the XDG desktop portal for dialogs
        };

        environment.variables = {
          QT_STYLE_OVERRIDE = "kvantum"; # Force kvantum style if possible
        };
      }
      (n.mkHomeFiles {
        ".config/Kvantum/kvantum.kvconfig".text = ''
          [General]
          theme=KvantumAlt
        '';

        ".config/qt6ct/qt6ct.conf".text = ''
          [Appearance]
          standard_dialogs=xdgdesktopportal
        '';
      })
    ]
  );
}
