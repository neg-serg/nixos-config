{
  pkgs,
  lib,
  config,
  neg,
  iosevkaNeg,
  ...
}:
let
  n = neg;
  alkano-aio = pkgs.callPackage ./alkano-aio.nix { };

  gtkThemeName = config.features.gui.gtkTheme or "Flight-Dark-GTK";
  gtkThemePkg = {
    "Flight-Dark-GTK" = pkgs.flight-gtk-theme;
    "Andromeda" = pkgs.andromeda-gtk-theme;
  }.${gtkThemeName} or pkgs.flight-gtk-theme;

  # GTK Settings
  gtkSettings = {
    "gtk-application-prefer-dark-theme" = 1;
    "gtk-cursor-theme-name" = "Alkano-aio";
    "gtk-cursor-theme-size" = 23;
    "gtk-font-name" = "Iosevka 10";
    "gtk-icon-theme-name" = "kora";
    "gtk-theme-name" = gtkThemeName;
  };

  gtkIni = lib.generators.toINI { } { Settings = gtkSettings; };

  # CSS to importing colors if needed
  cssContent = "/* @import 'colors.css'; */";
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
          # pkgs.pixora-icons # Icon theme
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
      (n.mkHomeFiles {
        ".config/gtk-3.0/settings.ini".text = gtkIni;
        ".config/gtk-3.0/gtk.css".text = cssContent;
        ".config/gtk-4.0/settings.ini".text = gtkIni;
        ".config/gtk-4.0/gtk.css".text = cssContent;

        ".gtkrc-2.0".text = ''
          gtk-theme-name="${gtkThemeName}"
          gtk-icon-theme-name="kora"
          gtk-font-name="Iosevka 10"
          gtk-cursor-theme-name="Alkano-aio"
          gtk-cursor-theme-size=23
          gtk-application-prefer-dark-theme=1
        '';

        # Wallust Config
        ".config/wallust/wallust.toml".source = ../../../../files/wallust/wallust.toml;
        ".config/wallust/templates/hyprland.conf".source =
          ../../../../files/wallust/templates/hyprland.conf;
        ".config/wallust/templates/kitty.conf".source = ../../../../files/wallust/templates/kitty.conf;
        ".config/wallust/templates/dunstrc".source = ../../../../files/wallust/templates/dunstrc;
      })
    ]
  );
}
