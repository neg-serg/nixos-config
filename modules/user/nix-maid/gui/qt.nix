{
  pkgs,
  config,
  lib,
  neg,
  ...
}:
let
  n = neg;
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
          # pkgs.qt5ct # Qt 5 configuration tool
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
          style=kvantum
          standard_dialogs=xdgdesktopportal
        '';

        # Kvantum не видит темы из nix store через XDG_DATA_DIRS (share/Kvantum
        # не пробрасывается в /run/current-system/sw/share/),
        # поэтому линкуем тему напрямую в ~/.local/share/Kvantum/.
        ".local/share/Kvantum/KvantumAlt/KvantumAlt.kvconfig".source =
          "${pkgs.kdePackages.qtstyleplugin-kvantum}/share/Kvantum/KvantumAlt/KvantumAlt.kvconfig";
        ".local/share/Kvantum/KvantumAlt/KvantumAlt.svg".source =
          "${pkgs.kdePackages.qtstyleplugin-kvantum}/share/Kvantum/KvantumAlt/KvantumAlt.svg";
      })
    ]
  );
}
