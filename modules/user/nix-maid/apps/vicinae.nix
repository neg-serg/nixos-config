{
  pkgs,
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.features.gui.vicinae;
  guiEnabled = config.features.gui.enable or false;
  enabled = guiEnabled && cfg.enable;

  iconTheme = config.features.gui.iconTheme or "kora";

  # Vicinae merges settings.json over built-in defaults.
  # Only keys set here override the defaults.
  vicinaeSettings = {
    terminal = "kitty";
    keybinding = "emacs";
    escape_key_behavior = "navigate_back";
    pop_on_backspace = true;
    pop_to_root_on_close = true;

    launcher_window = {
      size = {
        width = 920;
        height = 700;
      };
      client_side_decorations = {
        enabled = true;
        rounding = 4;
        border_width = 0;
        shadow_size = 8;
      };
      compact_mode = { enabled = true; };
    };

    font.normal = {
      family = "Iosevka Proportional Medium";
      size = 12;
    };

    theme = {
      dark = {
        name = "neg-dark";
        icon_theme = iconTheme;
      };
      light = {
        name = "neg-dark";
        icon_theme = iconTheme;
      };
    };

    # Flat keys — vicinae doesn't accept nested `action: { copy: … }`
    keybinds = {
      open-search-filter = "control+P";
      open-settings = "control+,";
      toggle-action-panel = "control+B";
      "action.copy" = "control+shift+C";
      "action.copy-name" = "control+shift+.";
      "action.copy-path" = "control+shift+,";
      "action.duplicate" = "control+D";
      "action.edit" = "control+E";
      "action.edit-secondary" = "control+shift+E";
      "action.move-down" = "Tab";
      "action.move-up" = "shift+Tab";
      "action.new" = "control+N";
      "action.open" = "control+O";
      "action.pin" = "control+shift+P";
      "action.refresh" = "control+R";
      "action.remove" = "control+X";
      "action.save" = "control+S";
    };

    providers = {
      system = {
        entrypoints = {
          browse-apps = { enabled = true; };
        };
      };
    };

    favorites = [
      "clipboard:history"
      "system:run"
      "system:browse-apps"
    ];
  };

  themeFile = ./../../../../files/gui/vicinae-theme.toml;
  settingsFile = pkgs.writeText "vicinae-settings.json" (builtins.toJSON vicinaeSettings);
in
{
  config = mkIf enabled (mkMerge [
    {
      environment.systemPackages = [
        pkgs.vicinae # Wayland-native app runner + window switcher
      ];

      systemd.user.services.vicinae = {
        enable = true;
        description = "Vicinae - Wayland application runner and window switcher";
        partOf = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${lib.getExe pkgs.vicinae} server";
          Restart = "always";
          RestartSec = 2;
          Environment = [
            "QT_QPA_PLATFORM=wayland"
            "WAYLAND_DISPLAY=wayland-1"
            "PATH=/run/current-system/sw/bin"
          ];
        };
      };
    }

    (mkIf cfg.manageConfig {
      # Deploy config via tmpfiles to user home — pure NixOS, no nix-maid
      systemd.user.tmpfiles.rules = [
        "L+ %h/.local/share/vicinae/themes/neg-dark.toml - - - - ${themeFile}"
        "L+ %h/.config/vicinae/settings.json - - - - ${settingsFile}"
      ];
    })
  ]);
}
