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
  proxyEnabled = config.features.net.proxy.enable or false;

  iconTheme = config.features.gui.iconTheme or "kora";
  themeFileKitty = ./../../../../files/gui/vicinae-theme-kitty.toml;

  # Vicinae merges settings.json over built-in defaults.
  # Only keys set here override the defaults.
  vicinaeSettings = {
    terminal = "kitty";
    keybinding = "emacs";
    escape_key_behavior = "navigate_back";
    pop_on_backspace = true;
    pop_to_root_on_close = true;

    # core behavior
    close_on_focus_loss = false;
    activate_on_single_click = false;
    consider_preedit = true;

    # telemetry + cache + encryption
    telemetry.system_info = false;
    pixmapCacheMb = 128;
    encryptSensitiveData = true;

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
      compact_mode = {
        enabled = true;
      };
      opacity = 0.92;
      material = "blur";
      layer_shell = {
        layer = "top";
        keyboard_interactivity = "on_demand";
      };
    };

    font.normal = {
      family = "Iosevka Proportional Medium";
      size = 12;
    };
    font.rendering = "qt";

    theme = {
      dark = {
        name = "neg-kitty";
        icon_theme = iconTheme;
      };
      light = {
        name = "neg-dark";
        icon_theme = iconTheme;
      };
    };

    header = {
      height = 60;
    };
    footer = {
      height = 40;
    };

    # search
    search_files_in_root = true;
    favicon_service = "twenty";
    fallbacks = [
      "files:search"
      "clipboard:history"
    ];

    # global shortcuts
    globalShortcuts = {
      toggle = "super+control+space";
    };
    input_server = {
      enabled = true;
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
          browse-apps = {
            enabled = true;
          };
          run = {
            preferences = {
              default-action = "run-in-terminal";
            };
          };
        };
      };
      clipboard = {
        preferences = {
          monitoring = true;
          ignorePasswords = true;
          eraseOnStartup = false;
        };
      };
      files = {
        preferences = {
          autoIndexing = true;
          indexingPaths = [ "/home/neg" ];
          excludedIndexingPaths = [
            "/home/neg/.cache"
            "/home/neg/.local/share/Trash"
          ];
        };
      };
      calculator = {
        preferences = {
          refreshRatesOnStartup = false;
        };
      };
      snippets = {
        preferences = {
          enabled = true;
          undo = true;
          keyDelay = "2";
          prePasteDelay = "0";
        };
      };
      power = {
        entrypoints = {
          lock = {
            preferences = {
              confirm = false;
            };
          };
          reboot = {
            preferences = {
              confirm = true;
            };
          };
          power-off = {
            preferences = {
              confirm = true;
            };
          };
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
          ]
          ++ lib.optional proxyEnabled "ALL_PROXY=socks5://127.0.0.1:10808";
        };
      };
    }

    (mkIf cfg.manageConfig {
      # Deploy config via tmpfiles to user home — pure NixOS, no nix-maid
      systemd.user.tmpfiles.rules = [
        "L+ %h/.local/share/vicinae/themes/neg-dark.toml - - - - ${themeFile}"
        "L+ %h/.local/share/vicinae/themes/neg-kitty.toml - - - - ${themeFileKitty}"
        "L+ %h/.config/vicinae/settings.json - - - - ${settingsFile}"
      ];
    })
  ]);
}
