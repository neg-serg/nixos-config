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

  iconTheme = config.features.gui.iconTheme or "kora";
in
{
  config = lib.mkIf (config.features.gui.enable or false) (
    lib.mkMerge [
      {
        # 1. Packages
        environment.systemPackages = [
          alkano-aio # Animated cursor theme
          pkgs.kora-icon-theme # Modern icon theme
          iosevkaNeg.nerd-font # Personalized Iosevka fonts with Nerd Font icons
        ];

        # 2. Environment Variables (Cursor)
        environment.sessionVariables = {
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
