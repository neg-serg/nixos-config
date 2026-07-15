{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
with lib;
let
  cfg = config.features.gui.vicinae;
  guiEnabled = config.features.gui.enable or false;
  enabled = guiEnabled && cfg.enable;

  iconTheme = config.features.gui.iconTheme or "kora";

  # ── vicinae theme (TOML) ───────────────────────────────────
  # Vicinae reads themes as TOML files from
  #   ~/.local/share/vicinae/themes/<name>.toml
  # and references them by [meta].name in settings.json.
  # See bundled themes under share/vicinae/themes/ for examples.
  vicinaeThemeToml = ''
    # Neg Dark — pure black, neutral gray borders, muted accents
    [meta]
    version = 1
    name = "Neg Dark"
    description = "Pure dark with neutral gray borders and muted accents."
    variant = "dark"

    [colors.core]
    background = "#000000"       # pure black
    foreground = "#9FABBA"       # 35% lighter than original #6c7e96
    secondary_background = "#080808"  # near-black
    border = "#333333"           # neutral gray (was deep blue)
    accent = "#4a4a4a"           # muted gray accent

    [colors.accents]
    blue = "#4a5555"
    green = "#3a6a51"
    magenta = "#7a6a8a"
    orange = "#8a6a40"
    purple = "#6a6a7a"
    red = "#5a2020"
    yellow = "#8a7a50"
    cyan = "#3a6a6a"

    [colors.list.item.selection]
    background = "#111111"
    secondary_background = "#1a1a1a"

    [colors.scrollbars]
    background = "#2a2a2a"

    [colors.loading]
    bar = "#555555"

    [colors.input]
    border = "#444444"
    border_focus = "#555555"
  '';

  # ── vicinae settings (JSON) ─────────────────────────────────
  # Written to ~/.config/vicinae/settings.json.
  # Vicinae merges it on top of compiled-in defaults:
  # only the keys you set here override the built-in config.
  # Tab / Shift+Tab navigate sections — built into the Qt UI,
  # no extra keybind needed.
  vicinaeSettings = {
    terminal = "kitty";

    keybinding = "default";
    escape_key_behavior = "navigate_back";
    pop_on_backspace = true;
    pop_to_root_on_close = true;

    # Window geometry (overrides built-in default 770×480)
    launcher_window = {
      size = {
        width = 680;
        height = 580;
      };
      # Minimal rounding, no outer frame border
      client_side_decorations = {
        enabled = true;
        rounding = 4;       # was 10 — less rounding
        border_width = 0;   # no border around the main window
        shadow_size = 8;
      };
    };

    # Font
    font = {
      normal = {
        family = "Iosevka Proportional Medium";
        size = 14;
      };
    };

    # Theme reference — filename stem of the TOML file in themes/
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

    # ── shortcuts ──────────────────────────────────
    # Flat keys (dot-delimited) — vicinae does NOT
    # accept nested `action: { copy: … }`.
    keybinds = {
      open-search-filter     = "control+P";
      open-settings          = "control+,";
      toggle-action-panel    = "control+B";

      "action.copy"            = "control+shift+C";
      "action.copy-name"       = "control+shift+.";
      "action.copy-path"       = "control+shift+,";
      "action.duplicate"       = "control+D";
      "action.edit"            = "control+E";
      "action.edit-secondary"  = "control+shift+E";
      "action.move-down"       = "control+shift+ARROWDOWN";
      "action.move-up"         = "control+shift+ARROWUP";
      "action.new"             = "control+N";
      "action.open"            = "control+O";
      "action.pin"             = "control+shift+P";
      "action.refresh"         = "control+R";
      "action.remove"          = "control+X";
      "action.save"            = "control+S";
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
          serviceConfig = {
            ExecStart = "${lib.getExe pkgs.vicinae} server";
            Restart = "always";
            RestartSec = 2;
            Environment = [
              "QT_QPA_PLATFORM=wayland"
              "WAYLAND_DISPLAY=wayland-1"
              # Include system PATH so launched apps (e.g. kvantummanager)
              # are found via their desktop-file Exec= command.
              "PATH=/run/current-system/sw/bin"
            ];
          };
        };
      }

      # Declarative config — only when manageConfig is true.
      # When false, vicinae manages its own theme/settings interactively.
      (mkIf cfg.manageConfig (
        neg.mkHomeFiles {
          # Theme file in vicinae's theme search path (TOML format)
          ".local/share/vicinae/themes/neg-dark.toml".text = vicinaeThemeToml;

          # Main config — merged on top of vicinae's built-in defaults
          ".config/vicinae/settings.json".text = builtins.toJSON vicinaeSettings;
        }
      ))
    ]
  );
}
