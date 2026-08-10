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

  iconTheme = config.features.gui.iconTheme or "kora-pgrey";
  themeFileKitty = ./../../../../files/gui/vicinae-theme-kitty.toml;

  # Vicinae merges settings.json over built-in defaults.
  # Only keys set here override the defaults.
  vicinaeSettings = {
    terminal = "kitty";
    keybinding = "emacs";
    escape_key_behavior = "close_window";
    pop_on_backspace = true;
    pop_to_root_on_close = true;

    # core behavior
    close_on_focus_loss = true;
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
      "@neg/wl-switcher:wprandom"
      "@neg/wl-switcher:wpgrid"
      "@neg/unsplash:wallpaper"
      "files:search"
      "clipboard:history"
    ];
    indexingPaths = [ "/home/neg" ];
    excludedIndexingPaths = [
      "/home/neg/.cache"
      "/home/neg/.local/share/Trash"
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
      toggle = "control+Return";
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
      "@neg/unsplash" = {
        preferences = {
          wallpaperPath = "~/pic/wl";
        };
      };
      "@neg/wl-switcher" = {
        preferences = {
          wallpaperPath = "~/pic/wl";
          transitionType = "random";
          transitionDuration = "0.5";
          transitionStep = "90";
          transitionFPS = "60";
          resize = "crop";
          upscale = "never";
          colorGenTool = "none";
          toggleVicinaeSetting = true;
          showImageDetails = true;
        };
      };
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

  # Nix-managed overrides — read-only, imported by the writable settings.json
  nixOverridesFile = pkgs.writeText "vicinae-nix-overrides.json" (builtins.toJSON vicinaeSettings);

  # Bootstrap script: creates a writable settings.json that imports the nix overrides.
  # Run once via ExecStartPre; after that, vicinae owns the file for GUI changes.
in
{
  config = mkIf enabled (mkMerge [
    {
      environment.systemPackages = [
        pkgs.vicinae # Wayland-native app runner + window switcher
        pkgs.wl # Vulkan wallpaper daemon (used by wl-switcher extension)
        pkgs.wl-switcher # vicinae extension for wl wallpaper switching
        pkgs.wallhaven # vicinae extension for wallhaven wallpaper browsing
        pkgs.noctwhspr # vicinae extension for hyprwhspr dictation control
        pkgs.skate # key-value store CLI (vicinae skate extension dep)
        # Wrapper: expose vicinae-browser-link from libexec to PATH
        (pkgs.writeShellScriptBin "vicinae-browser-link" ''
          exec ${pkgs.vicinae}/libexec/vicinae/vicinae-browser-link "$@"
        '')
      ];

      environment.etc."chromium/native-messaging-hosts/com.vicinae.vicinae.json".text = builtins.toJSON {
        name = "com.vicinae.vicinae";
        description = "Vicinae Native Messaging Host";
        path = "${pkgs.vicinae}/libexec/vicinae/vicinae-browser-link";
        type = "stdio";
        allowed_origins = [ "chrome-extension://chgfefjpcobfbnpmiokfjjaglahmnded/" ];
      };

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
      # Deploy config via tmpfiles to user home — pure NixOS, no nix-maid.
      # Settings.json is NOT symlinked here — it's writable for vicinae GUI edits.
      # Instead, nix-overrides.json (read-only) is imported by settings.json.
      systemd.user.tmpfiles.rules = [
        # Extension symlinks from Nix store to user vicinae extensions dir
        "L+ %h/.local/share/vicinae/extensions/wallhaven - - - - ${pkgs.wallhaven}"
        "L+ %h/.local/share/vicinae/extensions/noctwhspr - - - - ${pkgs.noctwhspr}"
        "L+ %h/.local/share/vicinae/extensions/wl-switcher - - - - ${pkgs.wl-switcher}"
        # C (copy) for themes: writable copy (mode 0644) so "Open Theme File" works.
        # Won't overwrite user edits (source has epoch mtime, dest is newer).
        "C %h/.local/share/vicinae/themes/neg-dark.toml 0644 - - - ${themeFile}"
        "C %h/.local/share/vicinae/themes/neg-kitty.toml 0644 - - - ${themeFileKitty}"
        "L+ %h/.config/vicinae/nix-overrides.json - - - - ${nixOverridesFile}"
      ];
    })
  ]);
}
