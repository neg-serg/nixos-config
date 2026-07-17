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
  gtkThemePkg = {
    "neg-gtk" = pkgs.flat-remix-gtk; # base widget structure, colors overridden via gtk.css
    "Flight-Dark-GTK" = pkgs.flight-gtk-theme;
    "Andromeda" = pkgs.andromeda-gtk-theme;
    "Flat-Remix-GTK-Blue-Darkest" = pkgs.flat-remix-gtk;
  }.${gtkThemeName} or pkgs.flight-gtk-theme;

  # GTK Settings
  gtkSettings = {
    "gtk-application-prefer-dark-theme" = 1;
    "gtk-cursor-theme-name" = "Alkano-aio";
    "gtk-cursor-theme-size" = 23;
    "gtk-font-name" = "Iosevka 10";
    "gtk-icon-theme-name" = iconTheme;
    "gtk-theme-name" = gtkThemeName;
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
          alkano-aio # Animated cursor theme
          gtkThemePkg # GTK theme (selected via features.gui.gtkTheme)
          pkgs.kora-icon-theme # Modern icon theme
          iosevkaNeg.nerd-font # Personalized Iosevka fonts with Nerd Font icons
        ];

        # 2. Environment Variables (Cursor + Theme)
        environment.sessionVariables = {
          GTK_THEME = gtkThemeName; # GTK theme for all apps
          XCURSOR_THEME = "Alkano-aio";
          XCURSOR_SIZE = "23";
          HYPRCURSOR_THEME = "Alkano-aio";
          HYPRCURSOR_SIZE = "23";
        };

        # 4. Fonts Config (NixOS level)
        fonts.fontconfig = {
          enable = true;
        };
      }
      # 5. GTK settings — theme, icons, cursors, fonts
      (neg.mkHomeFiles {
        ".config/gtk-3.0/settings.ini".text = gtkIni;
        ".config/gtk-3.0/gtk.css".text = cssContent;
        ".config/gtk-4.0/settings.ini".text = gtkIni;
        ".config/gtk-4.0/gtk.css".text = cssContent;

        ".gtkrc-2.0".text = ''
          gtk-theme-name="${gtkThemeName}"
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
