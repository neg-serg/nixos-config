{
  lib,
  pkgs,
  xdg,
  ...
}:
with {
  alkano-aio = pkgs.callPackage ./alkano-aio.nix {};
}; let
  kvantumAltConfig = xdg.mkXdgText "Kvantum/kvantum.kvconfig" ''
    [General]
    theme=KvantumAlt
  '';
in
  lib.mkMerge [
    {
      home = {
        pointerCursor = {
          gtk.enable = true;
          x11.enable = lib.mkForce false;
          package = lib.mkDefault alkano-aio;
          name = lib.mkDefault "Alkano-aio";
          size = lib.mkDefault 23;
        };
        sessionVariables = {
          XCURSOR_PATH = "${alkano-aio}/share/icons";
          XCURSOR_SIZE = 23;
          XCURSOR_THEME = "alkano-aio";
          # Keep Hyprland cursor in sync with the system cursor
          HYPRCURSOR_THEME = "Alkano-aio";
          HYPRCURSOR_SIZE = 23;
        };
      };

      fonts.fontconfig = {
        enable = true;
        defaultFonts = {
          serif = ["Cantarell"];
          sansSerif = ["Cantarell"];
          monospace = ["Iosevka"];
        };
      };

      gtk = {
        enable = true;

        font = {
          name = "Iosevka";
          size = 10;
        };

        cursorTheme = {
          name = "alkano-aio";
          package = alkano-aio;
          size = 23;
        };

        iconTheme = {
          name = "kora";
          package = pkgs.kora-icon-theme;
        };

        theme = {
          name = "Flight-Dark-GTK";
          package = pkgs.flight-gtk-theme;
        };

        gtk3 = {
          extraConfig.gtk-application-prefer-dark-theme = 1;
          extraCss = ''/*@import "colors.css";*/'';
        };

        gtk4 = {
          extraConfig.gtk-application-prefer-dark-theme = 1;
          extraCss = ''/*@import "colors.css";*/'';
        };
      };

      dconf = {
        enable = true;
        settings = {
          "org/gnome/desktop/interface" = {
            color-scheme = "prefer-dark";
            gtk-key-theme = "Emacs";
            icon-theme = "kora";
            font-hinting = "hintsfull";
            font-antialiasing = "grayscale";
          };
          "org/gnome/desktop/privacy".remember-recent-files = false;
          "org/gnome/desktop/screensaver".lock-enabled = false;
          "org/gnome/desktop/session".idle-delay = 0;
          "org/gtk/gtk4/settings/file-chooser" = {
            sort-directories-first = true;
            show-hidden = true;
            view-type = "list";
          };
          "org/gtk/settings/file-chooser" = {
            date-format = "regular";
            location-mode = "path-bar";
            show-hidden = false;
            show-size-column = true;
            show-type-column = true;
            sidebar-width = 189;
            sort-column = "name";
            sort-directories-first = false;
            sort-order = "descending";
            type-format = "category";
          };
        };
      };

      # stylix removed
    }
    kvantumAltConfig
  ]
