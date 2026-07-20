{
  pkgs,
  config,
  lib,
  neg,
  ...
}:
let
  qtEnabled = config.features.gui.qt.enable or false;
  iconTheme = config.features.gui.iconTheme or "kora-pgrey";
  kvantumTheme = "KvDark";
in
{
  config = lib.mkIf qtEnabled (
    lib.mkMerge [
      {
        environment.systemPackages = [
          pkgs.kdePackages.qt6ct
          pkgs.kdePackages.qtwayland
          pkgs.kdePackages.svgpart
        ];

        environment.sessionVariables = {
          QT_QPA_PLATFORMTHEME = "qt6ct";
          QT_XDG_DESKTOP_PORTAL = "1";
        };

        environment.variables = {
          QT_STYLE_OVERRIDE = "kvantum";
        };
      }
      {
        # Wrapped kvantummanager: set QT_PLUGIN_PATH for Wayland + SVG
        environment.systemPackages = let
          svg = "${pkgs.qt6.qtsvg}/${pkgs.qt6.qtbase.qtPluginPrefix}";
          wl = "${pkgs.kdePackages.qtwayland}/${pkgs.qt6.qtbase.qtPluginPrefix}";
          base = "${pkgs.qt6.qtbase}/${pkgs.qt6.qtbase.qtPluginPrefix}";
        in [
          (pkgs.writeShellApplication {
            name = "kvantummanager";
            runtimeInputs = [ pkgs.kdePackages.qtstyleplugin-kvantum ];
            text = ''
              export QT_PLUGIN_PATH="${svg}:${wl}:${base}"
              exec ${lib.getExe' pkgs.kdePackages.qtstyleplugin-kvantum "kvantummanager"}
            '';
          })
        ];
      }
      (neg.mkHomeFiles {
        ".config/Kvantum/kvantum.kvconfig".text = ''
          [General]
          theme=${kvantumTheme}
        '';
        ".config/qt6ct/qt6ct.conf".text = ''
          [Appearance]
          style=kvantum
          icon_theme=${iconTheme}
          standard_dialogs=xdgdesktopportal
        '';

        # Built-in themes
        ".config/Kvantum/KvDark/KvDark.kvconfig".source =
          "${pkgs.kdePackages.qtstyleplugin-kvantum}/share/Kvantum/KvDark/KvDark.kvconfig";
        ".config/Kvantum/KvDark/KvDark.svg".source =
          "${pkgs.kdePackages.qtstyleplugin-kvantum}/share/Kvantum/KvDark/KvDark.svg";
        ".config/Kvantum/KvArcDark/KvArcDark.kvconfig".source =
          "${pkgs.kdePackages.qtstyleplugin-kvantum}/share/Kvantum/KvArcDark/KvArcDark.kvconfig";
        ".config/Kvantum/KvArcDark/KvArcDark.svg".source =
          "${pkgs.kdePackages.qtstyleplugin-kvantum}/share/Kvantum/KvArcDark/KvArcDark.svg";
        ".config/Kvantum/KvSimplicityDark/KvSimplicityDark.kvconfig".source =
          "${pkgs.kdePackages.qtstyleplugin-kvantum}/share/Kvantum/KvSimplicityDark/KvSimplicityDark.kvconfig";
        ".config/Kvantum/KvSimplicityDark/KvSimplicityDark.svg".source =
          "${pkgs.kdePackages.qtstyleplugin-kvantum}/share/Kvantum/KvSimplicityDark/KvSimplicityDark.svg";

        # Catppuccin themes
        ".config/Kvantum/Catppuccin-Mocha-Blue/Catppuccin-Mocha-Blue.kvconfig".source = "${
          (pkgs.catppuccin-kvantum.override { variant = "mocha"; accent = "blue"; })
        }/share/Kvantum/Catppuccin-Mocha-Blue/Catppuccin-Mocha-Blue.kvconfig";
        ".config/Kvantum/Catppuccin-Mocha-Blue/Catppuccin-Mocha-Blue.svg".source = "${
          (pkgs.catppuccin-kvantum.override { variant = "mocha"; accent = "blue"; })
        }/share/Kvantum/Catppuccin-Mocha-Blue/Catppuccin-Mocha-Blue.svg";
        ".config/Kvantum/Catppuccin-Mocha-Mauve/Catppuccin-Mocha-Mauve.kvconfig".source = "${
          (pkgs.catppuccin-kvantum.override { variant = "mocha"; accent = "mauve"; })
        }/share/Kvantum/Catppuccin-Mocha-Mauve/Catppuccin-Mocha-Mauve.kvconfig";
        ".config/Kvantum/Catppuccin-Mocha-Mauve/Catppuccin-Mocha-Mauve.svg".source = "${
          (pkgs.catppuccin-kvantum.override { variant = "mocha"; accent = "mauve"; })
        }/share/Kvantum/Catppuccin-Mocha-Mauve/Catppuccin-Mocha-Mauve.svg";
        ".config/Kvantum/Catppuccin-Mocha-Lavender/Catppuccin-Mocha-Lavender.kvconfig".source = "${
          (pkgs.catppuccin-kvantum.override { variant = "mocha"; accent = "lavender"; })
        }/share/Kvantum/Catppuccin-Mocha-Lavender/Catppuccin-Mocha-Lavender.kvconfig";
        ".config/Kvantum/Catppuccin-Mocha-Lavender/Catppuccin-Mocha-Lavender.svg".source = "${
          (pkgs.catppuccin-kvantum.override { variant = "mocha"; accent = "lavender"; })
        }/share/Kvantum/Catppuccin-Mocha-Lavender/Catppuccin-Mocha-Lavender.svg";
        ".config/Kvantum/Catppuccin-Mocha-Sky/Catppuccin-Mocha-Sky.kvconfig".source = "${
          (pkgs.catppuccin-kvantum.override { variant = "mocha"; accent = "sky"; })
        }/share/Kvantum/Catppuccin-Mocha-Sky/Catppuccin-Mocha-Sky.kvconfig";
        ".config/Kvantum/Catppuccin-Mocha-Sky/Catppuccin-Mocha-Sky.svg".source = "${
          (pkgs.catppuccin-kvantum.override { variant = "mocha"; accent = "sky"; })
        }/share/Kvantum/Catppuccin-Mocha-Sky/Catppuccin-Mocha-Sky.svg";
        ".config/Kvantum/Catppuccin-Mocha-Green/Catppuccin-Mocha-Green.kvconfig".source = "${
          (pkgs.catppuccin-kvantum.override { variant = "mocha"; accent = "green"; })
        }/share/Kvantum/Catppuccin-Mocha-Green/Catppuccin-Mocha-Green.kvconfig";
        ".config/Kvantum/Catppuccin-Mocha-Green/Catppuccin-Mocha-Green.svg".source = "${
          (pkgs.catppuccin-kvantum.override { variant = "mocha"; accent = "green"; })
        }/share/Kvantum/Catppuccin-Mocha-Green/Catppuccin-Mocha-Green.svg";
      })
    ]
  );
}
