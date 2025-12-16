{
  pkgs,
  lib,
  config,
  iosevkaNeg, # Assumes this is passed in modules/user/nix-maid/default.nix args, or we need to pass it
  ...
}: let
  alkano-aio = pkgs.callPackage ./alkano-aio.nix {};

  # GTK Settings
  gtkSettings = {
    "gtk-application-prefer-dark-theme" = 1;
    "gtk-cursor-theme-name" = "Alkano-aio";
    "gtk-cursor-theme-size" = 23;
    "gtk-font-name" = "Iosevka 10";
    "gtk-icon-theme-name" = "kora";
    "gtk-theme-name" = "Flight-Dark-GTK";
  };

  gtkIni = lib.generators.toINI {} {Settings = gtkSettings;};

  # CSS to importing colors if needed, HM had it.
  cssContent = "/* @import 'colors.css'; */";
in {
  # Enable Logic handled in default.nix imports usually,
  # or we use a feature flag "features.gui.theme.enable"?
  # For now, let's assume it's part of core GUI or feature flags from feature flags.
  # HM module logic was "if config.features.gui.enable, set pointerCursor..."
  # We'll use lib.mkIf here using same features.

  config = lib.mkIf (config.features.gui.enable or false) {
    # 1. Packages
    environment.systemPackages = with pkgs; [
      alkano-aio
      flight-gtk-theme # Need to verify this exists in pkgs or overlay
      kora-icon-theme
      cantarell-fonts
      iosevkaNeg.nerd-font
    ];

    # 2. Environment Variables (Cursor)
    environment.sessionVariables = {
      # XCURSOR_PATH handles system icons automatically
      XCURSOR_THEME = "Alkano-aio";
      XCURSOR_SIZE = "23";
      HYPRCURSOR_THEME = "Alkano-aio";
      HYPRCURSOR_SIZE = "23";
    };

    # 3. GTK Config Files
    users.users.neg.maid.file.home = {
      ".config/gtk-3.0/settings.ini".text = gtkIni;
      ".config/gtk-3.0/gtk.css".text = cssContent;
      ".config/gtk-4.0/settings.ini".text = gtkIni;
      ".config/gtk-4.0/gtk.css".text = cssContent;

      # GTK2/Legacy ?
      ".gtkrc-2.0".text = ''
        gtk-theme-name="Flight-Dark-GTK"
        gtk-icon-theme-name="kora"
        gtk-font-name="Iosevka 10"
        gtk-cursor-theme-name="Alkano-aio"
        gtk-cursor-theme-size=23
        gtk-application-prefer-dark-theme=1
      '';
    };

    # 4. Fonts Config (NixOS level)
    fonts.fontconfig = {
      enable = true;
      defaultFonts = {
        serif = ["Cantarell"];
        sansSerif = ["Cantarell"];
        monospace = ["Iosevka"];
      };
    };
  };
}
