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
  kvantumTheme = "KvDark"; # Default dark theme — change after interactive selection via kvantummanager
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

        # === Kvantum Theme Configuration ===
        # Interactive selection workflow:
        #   1. Rebuild with nixos-rebuild switch
        #   2. Run: kvantummanager
        #   3. Browse themes in the GUI (KvDark, KvArcDark, KvSimplicityDark, Catppuccin-Mocha-*)
        #   4. Click a theme → "Use this theme" → "Apply"
        #   5. To lock in declaratively: change `kvantumTheme` variable above and rebuild
        #
        # Default theme: KvDark (pure dark, no white elements)
        # Built-in dark themes — deployed to ~/.config/Kvantum/ for KvantumManager discoverability
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
        ".config/Kvantum/Catppuccin-Mocha-Blue/Catppuccin-Mocha-Blue.kvconfig".source = "${
          (pkgs.catppuccin-kvantum.override {
            variant = "mocha";
            accent = "blue";
          })
        }/share/Kvantum/Catppuccin-Mocha-Blue/Catppuccin-Mocha-Blue.kvconfig";
        ".config/Kvantum/Catppuccin-Mocha-Blue/Catppuccin-Mocha-Blue.svg".source = "${
          (pkgs.catppuccin-kvantum.override {
            variant = "mocha";
            accent = "blue";
          })
        }/share/Kvantum/Catppuccin-Mocha-Blue/Catppuccin-Mocha-Blue.svg";
        ".config/Kvantum/Catppuccin-Mocha-Mauve/Catppuccin-Mocha-Mauve.kvconfig".source = "${
          (pkgs.catppuccin-kvantum.override {
            variant = "mocha";
            accent = "mauve";
          })
        }/share/Kvantum/Catppuccin-Mocha-Mauve/Catppuccin-Mocha-Mauve.kvconfig";
        ".config/Kvantum/Catppuccin-Mocha-Mauve/Catppuccin-Mocha-Mauve.svg".source = "${
          (pkgs.catppuccin-kvantum.override {
            variant = "mocha";
            accent = "mauve";
          })
        }/share/Kvantum/Catppuccin-Mocha-Mauve/Catppuccin-Mocha-Mauve.svg";
        ".config/Kvantum/Catppuccin-Mocha-Lavender/Catppuccin-Mocha-Lavender.kvconfig".source = "${
          (pkgs.catppuccin-kvantum.override {
            variant = "mocha";
            accent = "lavender";
          })
        }/share/Kvantum/Catppuccin-Mocha-Lavender/Catppuccin-Mocha-Lavender.kvconfig";
        ".config/Kvantum/Catppuccin-Mocha-Lavender/Catppuccin-Mocha-Lavender.svg".source = "${
          (pkgs.catppuccin-kvantum.override {
            variant = "mocha";
            accent = "lavender";
          })
        }/share/Kvantum/Catppuccin-Mocha-Lavender/Catppuccin-Mocha-Lavender.svg";
        ".config/Kvantum/Catppuccin-Mocha-Sky/Catppuccin-Mocha-Sky.kvconfig".source = "${
          (pkgs.catppuccin-kvantum.override {
            variant = "mocha";
            accent = "sky";
          })
        }/share/Kvantum/Catppuccin-Mocha-Sky/Catppuccin-Mocha-Sky.kvconfig";
        ".config/Kvantum/Catppuccin-Mocha-Sky/Catppuccin-Mocha-Sky.svg".source = "${
          (pkgs.catppuccin-kvantum.override {
            variant = "mocha";
            accent = "sky";
          })
        }/share/Kvantum/Catppuccin-Mocha-Sky/Catppuccin-Mocha-Sky.svg";
        ".config/Kvantum/Catppuccin-Mocha-Green/Catppuccin-Mocha-Green.kvconfig".source = "${
          (pkgs.catppuccin-kvantum.override {
            variant = "mocha";
            accent = "green";
          })
        }/share/Kvantum/Catppuccin-Mocha-Green/Catppuccin-Mocha-Green.kvconfig";
        ".config/Kvantum/Catppuccin-Mocha-Green/Catppuccin-Mocha-Green.svg".source = "${
          (pkgs.catppuccin-kvantum.override {
            variant = "mocha";
            accent = "green";
          })
        }/share/Kvantum/Catppuccin-Mocha-Green/Catppuccin-Mocha-Green.svg";
      })
    ]
  );
}
