{
  pkgs,
  lib,
  config,
  neg,
  iosevkaNeg,
  ...
}:
let
  alkano-aio = pkgs.callPackage ./alkano-aio.nix { };

  negGtkCss = builtins.readFile ../../../../files/gui/neg-gtk.css;

  iconTheme = config.features.gui.iconTheme or "kora-pgrey";

  gtkThemeName = config.features.gui.gtkTheme or "neg-gtk";

  # Map neg-gtk to real flat-remix variant; other names are their own themes
  realThemeName = {
    "neg-gtk" = "Flat-Remix-GTK-Blue-Darkest";
    "Flat-Remix-GTK-Blue-Darkest" = "Flat-Remix-GTK-Blue-Darkest";
  }.${gtkThemeName} or gtkThemeName;

  gtkThemePkg = {
    "neg-gtk" = pkgs.flat-remix-gtk;
    "Flat-Remix-GTK-Blue-Darkest" = pkgs.flat-remix-gtk;
    "Flight-Dark-GTK" = pkgs.flight-gtk-theme;
    "Andromeda" = pkgs.andromeda-gtk-theme;
  }.${gtkThemeName} or pkgs.flight-gtk-theme;

  # GTK Settings — use the real theme name so GTK finds the theme directory
  gtkSettings = {
    "gtk-application-prefer-dark-theme" = 1;
    "gtk-cursor-theme-name" = "Alkano-aio";
    "gtk-cursor-theme-size" = 23;
    "gtk-font-name" = "Iosevka 10";
    "gtk-icon-theme-name" = iconTheme;
    "gtk-theme-name" = realThemeName;
  };

  gtkIni = lib.generators.toINI { } { Settings = gtkSettings; };

  # GTK CSS override: neg.nvim colors for neg-gtk theme, else empty
  cssContent = if gtkThemeName == "neg-gtk" then negGtkCss else "/* @import 'colors.css'; */";
in
{
  config = lib.mkIf (config.features.gui.enable or false) (
    lib.mkMerge [
      {
        # 1. Packages
        environment.systemPackages = [
          alkano-aio
          gtkThemePkg
          pkgs.kora-icon-theme
          iosevkaNeg.nerd-font
        ];

        # 2. Environment Variables
        environment.sessionVariables = {
          GTK_THEME = gtkThemeName;
          XCURSOR_THEME = "Alkano-aio";
          XCURSOR_SIZE = "23";
          HYPRCURSOR_THEME = "Alkano-aio";
          HYPRCURSOR_SIZE = "23";
        };

        fonts.fontconfig = {
          enable = true;
        };
      }
      # 3. GTK settings + CSS + gtkrc
      (neg.mkHomeFiles {
        ".config/gtk-3.0/settings.ini".text = gtkIni;
        ".config/gtk-3.0/gtk.css".text = cssContent;
        ".config/gtk-4.0/settings.ini".text = gtkIni;
        ".config/gtk-4.0/gtk.css".text = cssContent;

        ".gtkrc-2.0".text = ''
          gtk-theme-name="${realThemeName}"
          gtk-icon-theme-name="${iconTheme}"
          gtk-font-name="Iosevka 10"
          gtk-cursor-theme-name="Alkano-aio"
          gtk-cursor-theme-size=23
          gtk-application-prefer-dark-theme=1
        '';
      })
    ]
  );
}
