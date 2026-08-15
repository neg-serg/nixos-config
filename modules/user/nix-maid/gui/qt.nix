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
  kvantumTheme = "KvCurves3d1";
in
{
  config = lib.mkIf qtEnabled (
    lib.mkMerge [
      {
        environment.systemPackages = [
          pkgs.kdePackages.qt6ct # Qt6 configuration tool
          pkgs.kdePackages.qtwayland # Qt6 Wayland platform plugin
          pkgs.kdePackages.svgpart # SVG viewer KPart
        ];
        environment.sessionVariables = {
          QT_QPA_PLATFORMTHEME = "qt6ct";
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
              runtimeInputs = [ pkgs.kdePackages.qtstyleplugin-kvantum ];
              text = ''
                export QT_PLUGIN_PATH="${svgPlugin}:${waylandPlugin}:${basePlugin}"
                exec ${lib.getExe' pkgs.kdePackages.qtstyleplugin-kvantum "kvantummanager"}
              '';
            })
          ];
      }
      (neg.mkHomeFiles {
        ".config/qt6ct/qt6ct.conf".text = ''
          [Appearance]
          style=kvantum
          icon_theme=${iconTheme}
          standard_dialogs=xdgdesktopportal
        '';

        # Kvantum themes for KvantumManager discovery (read-only symlinks is OK)
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

      })
      # Bootstrap writable kvantum.kvconfig (not a nix store symlink)
      # so KvantumManager can change the active theme via "Use this theme".
      {
        systemd.user.services.kvantum-bootstrap = {
          description = "Create writable Kvantum config (replace nix store symlink)";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe pkgs.bash} -c 'KVC=\"$HOME/.config/Kvantum/kvantum.kvconfig\"; [ -L \"$KVC\" ] && rm -f \"$KVC\"; if [ ! -f \"$KVC\" ]; then mkdir -p \"$(dirname \"$KVC\")\"; printf \"[General]\\ntheme=${kvantumTheme}\\n\" > \"$KVC\"; fi'";
          };
          after = [ "graphical-session.target" ];
          wants = [ "graphical-session.target" ];
          wantedBy = [ "graphical-session.target" ];
        };
      }
    ]
  );
}
