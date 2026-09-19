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

  negGtk3Css = builtins.readFile (config.lib.neg.path "files/gui/neg-gtk3.css");
  negGtk4Css = builtins.readFile (config.lib.neg.path "files/gui/neg-gtk4.css");

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

  # GTK CSS override: neg.nvim colors for neg-gtk theme, else empty.
  # GTK3 and GTK4 get separate files: libadwaita exposes a different (much
  # larger) set of named colors than GTK3's Adwaita.
  gtk3Css = if gtkThemeName == "neg-gtk" then negGtk3Css else "/* @import 'colors.css'; */";
  gtk4Css = if gtkThemeName == "neg-gtk" then negGtk4Css else "/* @import 'colors.css'; */";
in
{
  config = lib.mkIf (config.lib.neg.enabled "gui") (
    lib.mkMerge [
      {
        # 1. Packages
        environment.systemPackages = [
          alkano-aio
          gtkThemePkg
          pkgs.gsettings-desktop-schemas # org.gnome.desktop.interface schemas (dconf + libadwaita dark mode)
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
        # NOT from settings.ini (which only affects GTK apps directly).
        # color-scheme is what libadwaita apps actually use for dark mode.
        programs.dconf = {
          enable = true;
          profiles.user.databases = [
            {
              settings."org/gnome/desktop/interface" = {
                icon-theme = "'${iconTheme}'";
                gtk-theme = "'${realThemeName}'";
                cursor-theme = "'Alkano-aio'";
                font-name = "'Iosevka 10'";
                # libadwaita reads dark mode from color-scheme, not from GTK_THEME.
                color-scheme = "'prefer-dark'";
              };
            }
          ];
        };
      }
      # 3. GTK settings + CSS + gtkrc
      (neg.mkHomeFiles {
        ".config/gtk-3.0/settings.ini".text = gtkIni;
        ".config/gtk-3.0/gtk.css".text = gtk3Css;
        ".config/gtk-4.0/settings.ini".text = gtkIni;
        ".config/gtk-4.0/gtk.css".text = gtk4Css;

        ".config/gtk-2.0/gtkrc".text = ''
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
