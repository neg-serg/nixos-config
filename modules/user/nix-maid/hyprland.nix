{
  pkgs,
  lib,
  config,
  ...
}: let
  guiEnabled = config.features.gui.enable or false;
  hy3Enabled = config.features.gui.hy3.enable or false;

  # Static config files location
  hyprConfDir = ../../../files/gui/hypr;

  # Core static config files to link
  coreFiles = ["vars.conf" "classes.conf" "rules.conf" "autostart.conf"];

  # Binding files to link
  bindingFiles = [
    "resize.conf"
    "apps.conf"
    "special.conf"
    "wallpaper.conf"
    "tiling.conf"
    "tiling-helpers.conf"
    "media.conf"
    "notify.conf"
    "misc.conf"
    "hy3.conf"
    "selectors.conf"
    "_resets.conf"
  ];

  # hy3 plugin path
  hy3PluginPath = "${pkgs.hyprlandPlugins.hy3}/lib/libhy3.so";
  # Note: dynamic-cursors plugin disabled due to build failure with current Hyprland

  # --- Workspaces ---
  workspaces = [
    {
      id = 1;
      name = "︁ 𐌰:term";
      var = "term";
    }
    {
      id = 2;
      name = " 𐌱:web";
      var = "web";
    }
    {
      id = 3;
      name = " 𐌲:dev";
      var = "dev";
    }
    {
      id = 4;
      name = " 𐌸:games";
      var = "games";
    }
    {
      id = 5;
      name = " 𐌳:doc";
      var = "doc";
    }
    {
      id = 6;
      name = " 𐌴:draw";
      var = null;
    }
    {
      id = 7;
      name = " vid";
      var = "vid";
    }
    {
      id = 8;
      name = "✽ 𐌶:obs";
      var = "obs";
    }
    {
      id = 9;
      name = " 𐌷:pic";
      var = "pic";
    }
    {
      id = 10;
      name = " 𐌹:sys";
      var = null;
    }
    {
      id = 11;
      name = " 𐌺:vm";
      var = "vm";
    }
    {
      id = 12;
      name = " 𐌻:wine";
      var = "wine";
    }
    {
      id = 13;
      name = " 𐌼:patchbay";
      var = "patchbay";
    }
    {
      id = 14;
      name = " 𐌽:daw";
      var = "daw";
    }
    {
      id = 15;
      name = " 𐌾:dw";
      var = "dw";
    }
    {
      id = 16;
      name = " 𐌿:keyboard";
      var = "keyboard";
    }
    {
      id = 17;
      name = " 𐍀:im";
      var = "im";
    }
    {
      id = 18;
      name = " 𐍁:remote";
      var = "remote";
    }
    {
      id = 19;
      name = " Ⲣ:notes";
      var = "notes";
    }
    {
      id = 20;
      name = "𐍅:winboat";
      var = "winboat";
    }
    {
      id = 21;
      name = "𐍇:antigravity";
      var = "antigravity";
    }
  ];

  workspacesConf = let
    wsLines = builtins.concatStringsSep "\n" (map (w: "workspace = ${toString w.id}, defaultName:${w.name}") workspaces);
  in ''
    ${wsLines}

    workspace = w[tv1], gapsout:0, gapsin:0
    workspace = f[1], gapsout:0, gapsin:0
    windowrule = bordersize 0, floating:0, onworkspace:w[tv1]
    windowrule = rounding 0, floating:0, onworkspace:w[tv1]
    windowrule = bordersize 0, floating:0, onworkspace:f[1]
    windowrule = rounding 0, floating:0, onworkspace:f[1]

    # swayimg
    windowrulev2 = float, class:^(swayimg)$
    windowrulev2 = size 1200 800, class:^(swayimg)$
    windowrulev2 = move 100 100, class:^(swayimg)$
    windowrulev2 = tag swayimg, class:^(swayimg)$

    # gaming: immediate mode for low-latency input
    windowrulev2 = immediate, class:^(osu!|cs2)$

    # Bitwarden popup
    windowrulev2 = float, title:^(.*Bitwarden Password Manager.*)$

    # Calculator
    windowrulev2 = float, class:^(org.gnome.Calculator)$
    windowrulev2 = size 360 490, class:^(org.gnome.Calculator)$

    # Picture-in-Picture (browser video popup)
    windowrulev2 = float, title:^(Picture-in-Picture)$
    windowrulev2 = pin, title:^(Picture-in-Picture)$

    # special
    windowrulev2 = fullscreen, $pic
  '';

  routesConf = let
    routeLines = builtins.concatStringsSep "\n" (
      lib.filter (s: s != "") (
        map (
          w:
            if (w.var or null) != null
            then "windowrulev2 = workspace ${toString w.id}, $" + w.var
            else ""
        )
        workspaces
      )
    );
    tagLines = builtins.concatStringsSep "\n" (
      lib.filter (s: s != "") (
        map (
          w:
            if (w.var or null) != null
            then "windowrulev2 = tag " + w.var + ", $" + w.var
            else ""
        )
        workspaces
      )
    );
  in ''
    # routing
    windowrulev2 = noblur, $term
    # tags for workspace-routed classes
    ${tagLines}
    ${routeLines}
  '';

  # --- Permissions ---
  permissionsConf =
    ''
      ecosystem {
        enforce_permissions = 1
      }
      permission = ${lib.getExe pkgs.grim}, screencopy, allow
      permission = ${lib.getExe pkgs.hyprlock}, screencopy, allow
    ''
    + lib.optionalString hy3Enabled ''
      permission = ${hy3PluginPath}, plugin, allow
    '';

  # --- Main hyprland.conf ---
  hyprlandConf = ''
    env = GDK_SCALE,2
    env = STEAM_FORCE_DESKTOPUI_SCALING,2
    env = QT_AUTO_SCREEN_SCALE_FACTOR,1
    env = QT_ENABLE_HIGHDPI_SCALING,1
    env = XCURSOR_SIZE,23
    env = GDK_BACKEND,wayland
    env = QT_QPA_PLATFORM,wayland;xcb
    env = SDL_VIDEODRIVER,wayland,x11
    env = CLUTTER_BACKEND,wayland
    env = XDG_CURRENT_DESKTOP,Hyprland
    env = XDG_SESSION_DESKTOP,Hyprland
    env = XDG_SESSION_TYPE,wayland
    env = MOZ_ENABLE_WAYLAND,1
    env = ELECTRON_OZONE_PLATFORM_HINT,auto

    exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
    exec-once = systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP

    source = ~/.config/hypr/init.conf
    source = ~/.config/hypr/permissions.conf

    # User overrides live in ~/.config/hypr/local.d/*.conf (not managed by Nix)
    source = ~/.config/hypr/local.d/*.conf

    # Plugins
    ${lib.optionalString hy3Enabled "source = ~/.config/hypr/plugins.conf"}
  '';

  # --- Plugins config ---
  pluginsConf = lib.optionalString hy3Enabled ''
    # Hyprland plugins
    plugin = ${hy3PluginPath}
  '';

  # --- Pyprland config ---
  pyprlandConfig = {
    pyprland.plugins = [
      "fetch_client_menu"
      "scratchpads"
      "toggle_special"
    ];
    scratchpads = {
      im = {
        animation = "";
        command = "${lib.getExe pkgs.telegram-desktop}";
        class = "org.telegram.desktop";
        size = "30% 95%";
        position = "69% 2%";
        lazy = true;
        multi = true;
      };
      discord = {
        animation = "fromRight";
        command = "${lib.getExe pkgs.vesktop}";
        class = "vesktop";
        size = "50% 40%";
        lazy = true;
        multi = true;
      };
      music = {
        animation = "";
        command = "${lib.getExe pkgs.kitty} --class music -e ${lib.getExe pkgs.neg.rmpc}";
        margin = "80%";
        class = "music";
        position = "15% 50%";
        size = "70% 40%";
        lazy = true;
        unfocus = "hide";
      };
      torrment = {
        animation = "";
        command = "${lib.getExe pkgs.kitty} --class torrment -e ${lib.getExe pkgs.neg.tewi}";
        class = "torrment";
        position = "1% 0%";
        size = "98% 40%";
        lazy = true;
        unfocus = "hide";
      };
      teardown = {
        animation = "";
        command = "${lib.getExe pkgs.kitty} --class teardown -e ${lib.getExe pkgs.btop}";
        class = "teardown";
        position = "1% 0%";
        size = "98% 50%";
        lazy = true;
      };
      mixer = {
        animation = "fromRight";
        command = "${lib.getExe pkgs.pwvucontrol}";
        class = "com.saivert.pwvucontrol";
        lazy = true;
        size = "40% 90%";
        unfocus = "hide";
        multi = true;
      };
      teardrop = {
        animation = "fromTop";
        command = "${lib.getExe pkgs.hiddify-app} --class teardrop";
        class = "teardrop";
        size = "40% 90%";
        lazy = true;
        unfocus = "hide";
      };
    };
  };

  # Helper to generate TOML using pkgs.formats.toml
  tomlFormat = pkgs.formats.toml {};
  pyprlandToml = tomlFormat.generate "pyprland.toml" pyprlandConfig;
in
  lib.mkIf guiEnabled {
    environment.systemPackages =
      [
        pkgs.hyprlock # Hyprland's GPU-accelerated screen locking utility
        pkgs.hyprpolkitagent # Polkit authentication agent for Hyprland
        pkgs.playerctl # Command-line controller for media players
        pkgs.wayvnc # VNC server for wlroots-based Wayland compositors
        pkgs.wl-clipboard # Command-line copy/paste utilities for Wayland
        pkgs.wl-ocr # Wayland OCR tool
        pkgs.pyprland # Python plugin system for Hyprland
        # hyprmusic script
        (pkgs.writeScriptBin "hyprmusic" ''
          #!/bin/sh
          set -euo pipefail
          case "''${1:-}" in
            next) MEMBER=Next ;;
            previous) MEMBER=Previous ;;
            play) MEMBER=Play ;;
            pause) MEMBER=Pause ;;
            play-pause) MEMBER=PlayPause ;;
            *) echo "Usage: $0 next|previous|play|pause|play-pause"; exit 1 ;;
          esac
          exec dbus-send \
            --print-reply \
            --dest="org.mpris.MediaPlayer2.$(playerctl -l | head -n 1)" \
            /org/mpris/MediaPlayer2 \
            "org.mpris.MediaPlayer2.Player.$MEMBER"
        '')
        # hypr-reload script
        (pkgs.writeShellScriptBin "hypr-reload" ''
          set -euo pipefail
          # Reload Hyprland config (ignore failure to avoid spurious errors)
          hyprctl reload >/dev/null 2>&1 || true
          # Give Hypr a brief moment to settle before (re)starting quickshell
          sleep 0.15
          # Start quickshell only if not already active; 'start' is idempotent.
          systemctl --user start quickshell.service >/dev/null 2>&1 || true
        '')
        # hypr-start script (fixes race conditions)
        (pkgs.writeShellScriptBin "hypr-start" ''
          set -euo pipefail
          LOG="/tmp/hypr-start.log"
          echo "Starting hypr-start at $(date)" > "$LOG"

          # Wait a moment for Hyprland to fully initialize sockets
          sleep 1

          # Import environment
          echo "Importing environment..." >> "$LOG"
          dbus-update-activation-environment --systemd --all
          systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE

          # Stop any stale portals or session targets to force clean state
          echo "Cleaning stale session state..." >> "$LOG"
          systemctl --user stop xdg-desktop-portal xdg-desktop-portal-hyprland hyprland-session.target || true
          systemctl --user reset-failed

          # Start session
          echo "Starting hyprland-session.target..." >> "$LOG"
          systemctl --user start hyprland-session.target
          echo "Done." >> "$LOG"
        '')
        (pkgs.writeShellScriptBin "hyde-selector" (builtins.readFile ../../../files/scripts/hyde-selector.sh))
      ]
      ++ lib.optional hy3Enabled pkgs.hyprlandPlugins.hy3; # Tiling plugin for Hyprland inspired by i3/sway

    # --- Systemd user targets ---
    systemd.user.targets.hyprland-session = {
      unitConfig = {
        Description = "Hyprland compositor session";
        Documentation = ["man:systemd.special(7)"];
        BindsTo = ["graphical-session.target"];
        Wants = ["graphical-session-pre.target"];
        After = ["graphical-session-pre.target"];
      };
    };

    # --- User config files ---
    users.users.neg.maid.file.home = lib.mkMerge (
      [
        # Generated configs
        {".config/hypr/hyprland.conf".text = hyprlandConf;}
        {".config/hypr/workspaces.conf".text = workspacesConf;}
        {".config/hypr/rules-routing.conf".text = routesConf;}
        {".config/hypr/permissions.conf".text = permissionsConf;}
        {".config/hypr/pyprland.toml".source = pyprlandToml;}
      ]
      # Plugins config (hy3 only)
      ++ lib.optional hy3Enabled {".config/hypr/plugins.conf".text = pluginsConf;}
      # Static core config files
      ++ map (f: {".config/hypr/${f}".source = hyprConfDir + "/${f}";}) coreFiles
      # Init config (hy3 or nohy3)
      ++ [
        {
          ".config/hypr/init.conf".source =
            hyprConfDir
            + (
              if hy3Enabled
              then "/init.conf"
              else "/init.nohy3.conf"
            );
        }
      ]
      # Bindings config (hy3 or nohy3)
      ++ [
        {
          ".config/hypr/bindings.conf".source =
            hyprConfDir
            + (
              if hy3Enabled
              then "/bindings.conf"
              else "/bindings.nohy3.conf"
            );
        }
      ]
      # Static binding files
      ++ map (f: {".config/hypr/bindings/${f}".source = hyprConfDir + "/bindings/${f}";}) bindingFiles
      # Animation files
      ++ (let
        animDir = ../../../files/gui/hypr/animations;
        animFiles = builtins.attrNames (builtins.readDir animDir);
      in
        map (f: {".config/hypr/animations/${f}".source = animDir + "/${f}";}) animFiles)
      # Hyprlock files
      ++ (let
        lockDir = ../../../files/gui/hypr/hyprlock;
        lockFiles = builtins.attrNames (builtins.readDir lockDir);
      in
        map (f: {".config/hypr/hyprlock/${f}".source = lockDir + "/${f}";}) lockFiles)
      # Main hyprlock config (init)
      ++ [
        {".config/hypr/hyprlock.conf".source = ../../../files/gui/hypr/hyprlock/init.conf;}
      ]
    );

    # --- Systemd user services ---
    systemd.user.services = {
      # Hyprland Polkit Agent
      hyprpolkitagent = {
        description = "Hyprland Polkit Agent";
        wantedBy = ["graphical-session.target"];
        after = ["graphical-session-pre.target"];
        serviceConfig = {
          ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
          Environment = [
            "QT_QPA_PLATFORM=wayland"
            "XDG_SESSION_TYPE=wayland"
          ];
          Restart = "on-failure";
          RestartSec = "2s";
        };
      };

      # Pyprland service
      pyprland = {
        description = "Pyprland - Hyprland plugin system";
        wantedBy = ["graphical-session.target"];
        after = ["graphical-session-pre.target"];
        serviceConfig = {
          ExecStart = "${pkgs.pyprland}/bin/pypr";
          Restart = "always";
          RestartSec = "1";
        };
      };
    };
  }
