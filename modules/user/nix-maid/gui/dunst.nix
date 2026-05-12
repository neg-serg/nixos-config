{
  config,
  lib,
  pkgs,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  guiEnabled = config.features.gui.enable or false;

  # Browser helper logic from original HM module
  # Assuming web module is available, if not fallback to xdg-open
  # negLib logic was: db = negLib.web.defaultBrowser or {};
  # We might need to check if we can access similar config or just hardcode defaults for now.
  # For simplicity during migration, we'll default to xdg-open if the complex logic isn't easily reachable
  # or standard browser.
  browser = "${lib.getExe' pkgs.xdg-utils "xdg-open"}"; # Fallback/Simple default

  settings = {
    global = {
      alignment = "left";
      inherit browser;
      corner_radius = 4;
      ellipsize = "end";
      follow = "mouse";
      font = "Iosevka Medium 10";
      format = "<b>%s</b>\\n%b";
      background = "#000000";
      foreground = "#BFCAD0";
      frame_color = "#000000";
      frame_width = 10;
      gap_size = 4;
      height = "(0, 350)";
      hide_duplicate_count = true;
      horizontal_padding = 6;
      icon_path = "${pkgs.kora-icon-theme}/share/icons/kora/apps/scalable:${pkgs.kora-icon-theme}/share/icons/kora/status/scalable"; # Explicitly adding icon path helps if theme not globally set
      icon_position = "left";
      idle_threshold = 0;
      ignore_dbusclose = false;
      ignore_newline = false;
      indicate_hidden = true;
      line_height = 0;
      markup = "full";
      max_icon_size = 96;
      monitor = 0;
      notification_limit = 2;
      offset = "(0,54)";
      origin = "bottom-right";
      padding = 0;
      progress_bar = true;
      progress_bar_frame_width = 1;
      progress_bar_height = 6;
      progress_bar_max_width = 300;
      progress_bar_min_width = 150;
      scale = 0;
      separator_color = "frame";
      separator_height = 4;
      show_age_threshold = -1;
      show_indicators = false;
      sort = true;
      stack_duplicates = true;
      sticky_history = true;
      transparency = 14;
      vertical_alignment = "center";
      width = "(300, 500)";
      word_wrap = true;
    };

    urgency_low = {
      background = "#010204";
      foreground = "#BFCAD0";
      timeout = 4;
    };

    urgency_normal = {
      background = "#000000";
      foreground = "#BFCAD0";
      timeout = 10;
    };

    urgency_critical = {
      background = "#010204";
      foreground = "#BFCAD0";
      timeout = 0;
    };

    pic = {
      appname = "screenshot";
      format = "%s\\n%b";
      script = "~/.local/bin/pic-notify";
      urgency = "normal";
      background = "#010204";
      foreground = "#BFCAD0";
    };

    telegram = {
      appname = "Telegram Desktop";
      word_wrap = true;
      background = "#000000";
      foreground = "#BFCAD0";
    };
  };

  # Custom INI generator that quotes values starting with # to prevent dunst parsing as comments
  dunstrc =
    lib.generators.toINI {
      mkKeyValue =
        key: value:
        let
          v =
            if builtins.isString value && lib.hasPrefix "#" value then
              "\"${value}\""
            else if builtins.isBool value then
              if value then "true" else "false"
            else
              toString value;
        in
        "${key}=${v}";
    } settings
    + "\ninclude = ~/.cache/wallust/dunstrc\n";
in
lib.mkIf guiEnabled (
  lib.mkMerge [
    {
      # 2. Systemd user service
      systemd.user.services.dunst = {
        description = "Dunst notification daemon";
        after = [ "graphical-session-pre.target" ];
        partOf = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        serviceConfig = {
          Type = "dbus";
          BusName = "org.freedesktop.Notifications";
          ExecStart = "${lib.getExe pkgs.dunst} -config %h/.config/dunst/dunstrc"; # Lightweight and customizable notification daemon
          Restart = "on-failure";
        };
      };

      # Ensure packages are available
      environment.systemPackages = [
        pkgs.dunst # lightweight notification daemon for X11 and Wayland
        pkgs.kora-icon-theme # colorful icon theme for Linux desktops
        pkgs.libnotify # library for sending desktop notifications (provides notify-send)
      ];
    }

    # 1. Config file via nix-maid
    (n.mkHomeFiles {
      ".config/dunst/dunstrc".text = dunstrc;
    })
  ]
)
