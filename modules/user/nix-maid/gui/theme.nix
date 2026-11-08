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
  # neg-gtk maps to adw-gtk3-dark: its GTK3 half is a libadwaita port and uses
  # the same window_bg_color/accent_bg_color names as GTK4, so a single palette
  # (files/gui/neg-gtk{3,4}.css) recolors both toolkits.
  realThemeName =
    {
      "neg-gtk" = "adw-gtk3-dark";
      "Flat-Remix-GTK-Blue-Darkest" = "adw-gtk3-dark";
    }
    .${gtkThemeName} or gtkThemeName;

  # GTK4 keeps the built-in Adwaita: libadwaita apps ignore gtk-theme-name, and
  # adw-gtk3's gtk-4.0 directory is only a frozen copy of Adwaita.
  gtk4ThemeName = "Adwaita";

  gtkThemePkg =
    {
      "neg-gtk" = pkgs.adw-gtk3;
      "Flat-Remix-GTK-Blue-Darkest" = pkgs.adw-gtk3;
      "Adwaita-dark" = pkgs.adw-gtk3;
    }
    .${gtkThemeName} or pkgs.adw-gtk3;

  # GTK Settings — use the real theme name so GTK finds the theme directory.
  # Settings are written per toolkit (no GTK_THEME session variable): GTK_THEME
  # overrides gtk-theme-name for all GTK versions at once, which would pin GTK3
  # to the GTK4 theme.
  gtk3Settings = {
    "gtk-application-prefer-dark-theme" = 1;
    "gtk-cursor-theme-name" = "Alkano-aio";
    "gtk-cursor-theme-size" = 23;
    "gtk-font-name" = "Iosevka 10";
    "gtk-icon-theme-name" = iconTheme;
    "gtk-theme-name" = realThemeName;
  };

  gtk4Settings = gtk3Settings // {
    "gtk-theme-name" = gtk4ThemeName;
  };

  gtk3Ini = lib.generators.toINI { } { Settings = gtk3Settings; };
  gtk4Ini = lib.generators.toINI { } { Settings = gtk4Settings; };

  # GTK CSS override: neg.nvim colors for neg-gtk theme, else empty.
  # GTK3 and GTK4 get separate files: libadwaita exposes a different (much
  # larger) set of named colors than GTK3's Adwaita.
  gtk3Css = if gtkThemeName == "neg-gtk" then negGtk3Css else "/* @import 'colors.css'; */";
  gtk4Css = if gtkThemeName == "neg-gtk" then negGtk4Css else "/* @import 'colors.css'; */";

  # GSettings schemas for the whole session. This is not a GNOME session, so
  # nothing links the installed packages' `share/gsettings-schemas` into the
  # system profile and GSettings found no schemas at all: an unwrapped
  # GLib/GTK4 program (Vivaldi/Chromium is the visible one) silently fell back
  # to GtkSettings' defaults — icon theme "Adwaita" instead of Kora, no
  # prefer-dark, stock fonts. Vivaldi then drew every image in its downloads
  # panel with Adwaita's 16 px `image-x-generic` bitmap, upscaled and blurry.
  # GTK3 apps read `~/.config/gtk-3.0/settings.ini`, but GTK4 takes the theme
  # from `org.gnome.desktop.interface`, i.e. from GSettings/dconf, and needs
  # the schema present for that lookup to work.
  #
  # Two halves, because the two paths have different reach:
  #
  # - the system profile gets the desktop schemas through `pathsToLink`: every
  #   process already has `/run/current-system/sw/share` on XDG_DATA_DIRS, so
  #   this is live right after the generation is switched;
  # - the session variable below points at each package's own compiled
  #   database and also adds GTK's schemas (`org.gtk.Settings.*`), but it only
  #   reaches programs started after the next login.
  #
  # No merged directory: glib-compile-schemas reads the files in readdir order
  # and silently ignores a schema whose enum is defined in a file it has not
  # reached yet, so merging the packages' XML into one dir yields a database
  # that is missing half the schemas.
  gsettingsProfileSchemas = pkgs.runCommand "gsettings-profile-schemas" { } ''
    mkdir -p $out/share/glib-2.0
    ln -s ${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas $out/share/glib-2.0/schemas
  '';

  # One colon-separated list: every package ships its own compiled database.
  gsettingsSchemaDir =
    lib.concatMapStringsSep ":" (p: "${p}/share/gsettings-schemas/${p.name}/glib-2.0/schemas")
      [
        pkgs.gsettings-desktop-schemas # org.gnome.desktop.interface (icon theme, dark mode)
        pkgs.gtk3 # org.gtk.Settings.* for GTK3
        pkgs.gtk4 # org.gtk.gtk4.Settings.* for GTK4
      ];
in
{
  config = lib.mkIf (config.lib.neg.enabled "gui") (
    lib.mkMerge [
      {
        # 1. Packages
        environment.systemPackages = [
          alkano-aio
          gtkThemePkg
          gsettingsProfileSchemas # desktop schemas on the profile's XDG_DATA_DIRS
          pkgs.gsettings-desktop-schemas # org.gnome.desktop.interface schemas (dconf + libadwaita dark mode)
          pkgs.kora-icon-theme # flat icon theme
          iosevkaNeg.nerd-font
        ];

        # `gsettingsProfileSchemas` puts its compiled database at this prefix,
        # which the profile's XDG_DATA_DIRS entry already exposes.
        environment.pathsToLink = [ "/share/glib-2.0/schemas" ];

        # 2. Environment Variables
        environment.sessionVariables = {
          # See `gsettingsSchemaDir`: without this every unwrapped GTK4 app
          # (Vivaldi, zenity, …) reads GSettings defaults instead of dconf.
          GSETTINGS_SCHEMA_DIR = gsettingsSchemaDir;
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
                # Plain strings: the dconf module wraps them as GVariant "s".
                # Quotes added here would become part of the value, which
                # silently breaks enum keys such as color-scheme.
                icon-theme = iconTheme;
                gtk-theme = realThemeName;
                cursor-theme = "Alkano-aio";
                font-name = "Iosevka 10";
                # libadwaita reads dark mode from color-scheme, not from GTK_THEME.
                color-scheme = "prefer-dark";
              };
            }
          ];
        };
      }
      # 3. GTK settings + CSS + gtkrc
      (neg.mkHomeFiles {
        ".config/gtk-3.0/settings.ini".text = gtk3Ini;
        ".config/gtk-3.0/gtk.css".text = gtk3Css;
        ".config/gtk-4.0/settings.ini".text = gtk4Ini;
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
