{
  pkgs,
  lib,
  config,
  neg,
  impurity ? null,
  iosevkaNeg,
  ...
}:
let
  n = neg impurity;
  alkano-aio = pkgs.callPackage ./alkano-aio.nix { };

  # GTK Settings
  gtkSettings = {
    "gtk-application-prefer-dark-theme" = 1;
    "gtk-cursor-theme-name" = "Alkano-aio";
    "gtk-cursor-theme-size" = 23;
    "gtk-font-name" = "Iosevka 10";
    "gtk-icon-theme-name" = "kora";
    "gtk-theme-name" = "Flight-Dark-GTK";
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
          pkgs.flight-gtk-theme # Dark GTK theme
          pkgs.kora-icon-theme # Modern icon theme
          pkgs.cantarell-fonts # Default GNOME fonts
          iosevkaNeg.nerd-font # Personalized Iosevka fonts with Nerd Font icons
        ];

        # 2. Environment Variables (Cursor + Theme)
        environment.sessionVariables = {
          GTK_THEME = "Flight-Dark-GTK"; # Force GTK theme for all apps
          XCURSOR_THEME = "Alkano-aio";
          XCURSOR_SIZE = "23";
          HYPRCURSOR_THEME = "Alkano-aio";
          HYPRCURSOR_SIZE = "23";
        };

        # 4. Fonts Config (NixOS level)
        fonts.fontconfig = {
          enable = true;
          defaultFonts = {
            serif = [ "Cantarell" ];
            sansSerif = [ "Cantarell" ];
            monospace = [ "Iosevka" ];
          };
        };
      }
      (n.mkHomeFiles {
        ".config/gtk-3.0/settings.ini".text = gtkIni;
        ".config/gtk-3.0/gtk.css".text = cssContent;
        ".config/gtk-4.0/settings.ini".text = gtkIni;
        ".config/gtk-4.0/gtk.css".text = cssContent;

        ".gtkrc-2.0".text = ''
          gtk-theme-name="Flight-Dark-GTK"
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
