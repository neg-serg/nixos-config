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
      # 5. GTK settings — tell apps/browsers system prefers dark
      (neg.mkHomeFiles {
        ".config/gtk-3.0/settings.ini".text = ''
          [Settings]
          gtk-application-prefer-dark-theme = 1
        '';
        ".config/gtk-4.0/settings.ini".text = ''
          [Settings]
          gtk-application-prefer-dark-theme = 1
        '';
      })
    ]
  );
}
