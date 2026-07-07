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
      urgent = "#8A2F58";
      scrollbar = "#1c334e";
      loading_bar = "#006FCC";
    };
    fonts = {
      main = "Outfit 13";
      secondary = "Outfit 11";
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
          serviceConfig = {
            ExecStart = "${lib.getExe pkgs.vicinae} server";
            Restart = "always";
            RestartSec = 2;
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
