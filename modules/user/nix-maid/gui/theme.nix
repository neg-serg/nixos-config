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

  negGtkCss = builtins.readFile (config.lib.neg.path "files/gui/neg-gtk.css");

  iconTheme = config.features.gui.iconTheme or "kora-pgrey";

  gtkThemeName = config.features.gui.gtkTheme or "neg-gtk";

  # nixos-unstable removed the GTK2/murrine-based themes (flat-remix-gtk,
  # flight-gtk-theme, andromeda-gtk-theme) — they were dropped upstream.
  # Use the available modern GTK theme (adw-gtk3, "Adwaita-dark") as the
  # migration default; Flat-Remix variants no longer build in unstable.
  realThemeName =
    {
      "neg-gtk" = "Adwaita-dark";
      "Flat-Remix-GTK-Blue-Darkest" = "Adwaita-dark";
    }
    .${gtkThemeName} or gtkThemeName;

  gtkThemePkg =
    {
      "neg-gtk" = pkgs.adw-gtk3;
      "Flat-Remix-GTK-Blue-Darkest" = pkgs.adw-gtk3;
      "Adwaita-dark" = pkgs.adw-gtk3;
    }
    .${gtkThemeName} or pkgs.adw-gtk3;

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
  config = lib.mkIf (config.lib.neg.enabled "gui") (
    lib.mkMerge [
      {
        # 1. Packages
        environment.systemPackages = [
          alkano-aio
          gtkThemePkg
          pkgs.kora-icon-theme # flat icon theme
          iosevkaNeg.nerd-font
        ];

        # 2. Environment Variables
        environment.sessionVariables = {
          GTK_THEME = realThemeName;
          XCURSOR_THEME = "Alkano-aio";
          XCURSOR_SIZE = "23";
          HYPRCURSOR_THEME = "Alkano-aio";
          HYPRCURSOR_SIZE = "23";
        };

        fonts.fontconfig = {
          enable = true;
        };

        # dconf/GSettings — xdg-desktop-portal-gtk reads icon theme from here,
        # NOT from settings.ini (which only affects GTK apps directly)
        programs.dconf = {
          enable = true;
          profiles.user.databases = [
            {
              settings."org/gnome/desktop/interface" = {
                icon-theme = "'${iconTheme}'";
                gtk-theme = "'${realThemeName}'";
                cursor-theme = "'Alkano-aio'";
                font-name = "'Iosevka 10'";
              };
            }
          ];
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
