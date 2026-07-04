{
  pkgs,
  lib,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  # Vicinae theme definition (neg)
  # Vicinae Flight-Dark theme (ported from legacy Salt config: flight-dark.toml)
  # Color palette harmonized with Flight-Dark-GTK, Rofi, and Kitty.
  vicinaeThemeNeg =
    let
      font = "Outfit";
    in
    {
      window = {
        width = 750;
        height = 420;
        border_width = 1;
        border_radius = 1;
        margin = 10;
        padding = 10;
      };
      colors = {
        background = "#000000";
        border = "#0B2536";
        text = "#CBD6E5";
        accent = "#006FCC";
        selected_background = "#122337";
        selected_text = "#E2EBF5";
        urgent = "#8A2F58"; # error red from theme palette
        scrollbar = "#1c334e";
        loading_bar = "#006FCC";
      };
      fonts = {
        main = "${font} 13";
        secondary = "${font} 11";
      };
    };

  # Vicinae settings
  vicinaeSettings = {
    terminal = "kitty";
    launcher = {
      show_icons = true;
      icon_theme = "Papirus-Dark";
      scan_desktop_files = true;
    };
  };
in
lib.mkMerge [
  {
    environment.systemPackages = [
      pkgs.vicinae # Wayland-native application runner and window switcher
      pkgs.rofi-pass-wayland # Rofi frontend for pass (password store)
    ];

    # Vicinae Systemd Service
    systemd.user.services.vicinae = {
      enable = true;
      description = "Vicinae - Wayland application runner and window switcher";
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.vicinae} server"; # Native, fast, extensible launcher for the desktop
        Restart = "always";
        RestartSec = 2;
      };
    };
  }

  (n.mkHomeFiles {
    # Thematic config

    # Thematic config (can be static or linked)
    ".config/vicinae/theme.json".text = builtins.toJSON vicinaeThemeNeg;
    ".config/vicinae/settings.json".text = builtins.toJSON vicinaeSettings;
  })
]
