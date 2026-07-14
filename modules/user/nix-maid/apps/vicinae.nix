{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
with lib;
let
  n = neg;
  cfg = config.features.gui.vicinae;
  guiEnabled = config.features.gui.enable or false;
  enabled = guiEnabled && cfg.enable;

  # Declarative theme (only when manageConfig = true)
  iconTheme = config.features.gui.iconTheme or "kora";
  vicinaeTheme = {
    window = {
      # Squarer, more compact proportions — neg-style strict geometry
      width = 620;
      height = 540;
      border_width = 2;   # thicker frame = stricter look
      border_radius = 0;  # zero rounding = strict square
      margin = 8;         # tighter outer spacing
      padding = 12;       # more internal breathing room for large font
    };
    # Palette adapted from neg.nvim — pure-dark with signature deep-blue accents
    colors = {
      background = "#000000";   # neg.bclr — pure black
      border = "#005faf";       # neg.ops3 — signature deep blue accent
      text = "#6c7e96";         # neg.norm — muted blue-gray foreground
      accent = "#005faf";       # neg.ops3 — deep blue accent
      selected_background = "#0d1824"; # neg.selection_bg — very dark blue
      selected_text = "#d1e5ff";       # neg.whit — light blue-white
      urgent = "#6b0f2a";       # neg.dred — dark burgundy for errors
      scrollbar = "#1c334e";    # neg.col8 — dark blue-gray
      loading_bar = "#005faf";  # neg.ops3 — accent blue
    };
    fonts = {
      main = "Outfit 20";      # was 13 — much larger, bold presence
      secondary = "Outfit 16";  # was 11 — much larger
    };
  };

  vicinaeSettings = {
    terminal = "kitty";
    launcher = {
      show_icons = true;
      icon_theme = iconTheme;
      scan_desktop_files = true;
    };
  };
in
{
  config = mkIf enabled (
    mkMerge [
      {
        environment.systemPackages = [
          pkgs.vicinae # Wayland-native application runner and window switcher
        ];

        systemd.user.services.vicinae = {
          enable = true;
          description = "Vicinae - Wayland application runner and window switcher";
          partOf = [ "graphical-session.target" ];
          wantedBy = [ "graphical-session.target" ];
          after = [ "graphical-session.target" ];
          # Set Qt platform to Wayland explicitly — avoids crash when DISPLAY/Wayland
          # socket isn't inherited properly from the session scope.
          serviceConfig = {
            ExecStart = "${lib.getExe pkgs.vicinae} server";
            Restart = "always";
            RestartSec = 2;
            Environment = [
              "QT_QPA_PLATFORM=wayland"
              "WAYLAND_DISPLAY=wayland-1"
            ];
          };
        };
      }

      # Declarative config — only when manageConfig is true.
      # When false, vicinae manages its own theme/settings interactively.
      (mkIf cfg.manageConfig (
        n.mkHomeFiles {
          ".config/vicinae/theme.json".text = builtins.toJSON vicinaeTheme;
          ".config/vicinae/settings.json".text = builtins.toJSON vicinaeSettings;
        }
      ))
    ]
  );
}
