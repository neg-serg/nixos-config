{
  pkgs,
  config,
  lib,
  neg,
  ...
}:
let
  qtEnabled = config.lib.neg.enabled "gui.qt";
  iconTheme = config.features.gui.iconTheme or "kora-pgrey";
  # Qt6 Kvantum bridge: owns the style plugin plus the bundled themes and their
  # matching .colors schemes.
  kvantumPkg = pkgs.kdePackages.qtstyleplugin-kvantum;
  # Neutral dark theme with a blue selection, which is what the panel palette
  # (#006FCC accent on a near-black surface) asks for. Must be a theme shipped by
  # kvantumPkg (or symlinked under ~/.config/Kvantum below); changing it switches
  # both the widgets and the platform-theme palette.
  kvantumTheme = "KvSimplicityDark";
in
{
  config = lib.mkIf qtEnabled (
    lib.mkMerge [
      {
        environment.systemPackages = [
          pkgs.kdePackages.qt6ct # Qt6 configuration tool
          pkgs.kdePackages.qtwayland # Qt6 Wayland platform plugin
        ];
        environment.sessionVariables = {
          QT_QPA_PLATFORMTHEME = "hyprqt6engine";
          QT_XDG_DESKTOP_PORTAL = "1";
        };
      }
      {
        # Wrapped kvantummanager: set QT_PLUGIN_PATH for Wayland + SVG
        environment.systemPackages =
          let
            svgPlugin = "${pkgs.qt6.qtsvg}/${pkgs.qt6.qtbase.qtPluginPrefix}";
            waylandPlugin = "${pkgs.kdePackages.qtwayland}/${pkgs.qt6.qtbase.qtPluginPrefix}";
            basePlugin = "${pkgs.qt6.qtbase}/${pkgs.qt6.qtbase.qtPluginPrefix}";
          in
          [
            (pkgs.writeShellApplication {
              name = "kvantummanager";
              runtimeInputs = [ kvantumPkg ];
              text = ''
                export QT_PLUGIN_PATH="${svgPlugin}:${waylandPlugin}:${basePlugin}"
                exec ${lib.getExe' kvantumPkg "kvantummanager"}
              '';
            })
          ];
      }
      (neg.mkHomeFiles {
        # hyprqt6engine reads its own hyprlang config; keep it beside the qt6ct
        # one so a switch is just a flip of QT_QPA_PLATFORMTHEME. The style is
        # the same Kvantum theme the qt6ct config selects, the palette comes
        # from Kvantum's matching .colors file (KF6ColorScheme), and the icon
        # theme matches the system-wide one.
        ".config/hypr/hyprqt6engine.conf".text = ''
          # Managed by features.gui.qt (modules/user/nix-maid/gui/qt.nix).
          theme {
            style = kvantum
            color_scheme = ${kvantumPkg}/share/color-schemes/${kvantumTheme}.colors
            icon_theme = ${iconTheme}
          }
        '';

        # Active Kvantum theme. Kvantum's style plugin reads this file only, so the
        # name has to match the `color_scheme` above: pointing it at a theme dir
        # without a <name>/<name>.kvconfig (e.g. a leftover of a removed theme)
        # makes Kvantum fall back to its builtin default and the palette stops
        # matching the widgets. Declarative on purpose — KvantumManager's "Use this
        # theme" writes are reverted on the next switch.
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

        # Kvantum themes for KvantumManager discovery (read-only symlinks is OK)
        ".config/Kvantum/KvDark/KvDark.kvconfig".source =
          "${kvantumPkg}/share/Kvantum/KvDark/KvDark.kvconfig";
        ".config/Kvantum/KvDark/KvDark.svg".source = "${kvantumPkg}/share/Kvantum/KvDark/KvDark.svg";
        ".config/Kvantum/KvArcDark/KvArcDark.kvconfig".source =
          "${kvantumPkg}/share/Kvantum/KvArcDark/KvArcDark.kvconfig";
        ".config/Kvantum/KvArcDark/KvArcDark.svg".source =
          "${kvantumPkg}/share/Kvantum/KvArcDark/KvArcDark.svg";
        ".config/Kvantum/KvSimplicityDark/KvSimplicityDark.kvconfig".source =
          "${kvantumPkg}/share/Kvantum/KvSimplicityDark/KvSimplicityDark.kvconfig";
        ".config/Kvantum/KvSimplicityDark/KvSimplicityDark.svg".source =
          "${kvantumPkg}/share/Kvantum/KvSimplicityDark/KvSimplicityDark.svg";

      })
    ]
  );
}
