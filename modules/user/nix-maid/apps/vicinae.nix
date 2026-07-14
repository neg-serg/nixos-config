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

  # Full config sent to ~/.config/vicinae/settings.json.
  # Merged-on-top of vicinae's built-in defaults (see `vicinae config default`).
  # Tab / Shift+Tab navigation between sections is built into the Qt UI and
  # works out of the box — no extra keybind needed.
  vicinaeSettings = {
    terminal = "kitty";

    # ── navigation —─────────────
    # "default" (Tab between sections) vs "emacs" (Ctrl+N/P)
    keybinding = "default";
    escape_key_behavior = "navigate_back";
    pop_on_backspace = true;
    pop_to_root_on_close = true;   # reset section on window close

    launcher = {
      show_icons = true;
      icon_theme = iconTheme;
      scan_desktop_files = true;
    };

    # ── common shortcuts —───────
    # Listed explicitly so they survive a `manageConfig = true` reset.
    # Only keys listed here are recognised by vicinae; there is no
    # "next-section" key — use Tab / Shift+Tab for that.
    keybinds = {
      open-search-filter     = "control+P";
      open-settings          = "control+,";
      toggle-action-panel    = "control+B";

      action.copy            = "control+shift+C";
      action.copy-name       = "control+shift+.";
      action.copy-path       = "control+shift+,";
      action.duplicate       = "control+D";
      action.edit            = "control+E";
      action.edit-secondary  = "control+shift+E";
      action.move-down       = "control+shift+ARROWDOWN";
      action.move-up         = "control+shift+ARROWUP";
      action.new             = "control+N";
      action.open            = "control+O";
      action.pin             = "control+shift+P";
      action.refresh         = "control+R";
      action.remove          = "control+X";
      action.save            = "control+S";
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
        neg.mkHomeFiles {
          ".config/vicinae/theme.json".text = builtins.toJSON vicinaeTheme;
          ".config/vicinae/settings.json".text = builtins.toJSON vicinaeSettings;
        }
      ))
    ]
  );
}
