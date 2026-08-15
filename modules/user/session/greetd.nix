{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  guiEnabled = config.features.gui.enable or true;
  mainUser = config.users.main.name or "neg";
  mainHome =
    if builtins.hasAttr mainUser config.users.users then
      config.users.users.${mainUser}.home or "/home/${mainUser}"
    else
      "/home/${mainUser}";
  greeterCache = "/home/greeter/.cache";
  greeterWallpaperDst = "${greeterCache}/greeter-wallpaper";
  # Fallback when no dynamic source yields a file at activation time.
  greeterWallpaperFallback = "${mainHome}/pic/wl/waterfall_jungle_dark_150290_3840x2400.jpg";
  hyprlandConfig = pkgs.writeText "greetd-hyprland-config" ''
    monitorv2 {
      output = DP-2
      mode = 3840x2160@240
      position = 0x0
      scale = 1
    }
    monitorv2 {
      output = DP-1
      disabled = true
    }
    env = HOME,/home/greeter
    env = XDG_CACHE_HOME,/home/greeter/.cache
    env = XDG_CONFIG_HOME,/home/greeter/.config
    env = XDG_DATA_HOME,/home/greeter/.local/share
    exec-once = ${lib.getExe pkgs.bash} -c "HOME=/home/greeter QML2_IMPORT_PATH=/etc/greetd/quickshell ${
      lib.getExe inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default
    } -p /etc/greetd/quickshell/greeter/greeter.qml > /tmp/qs-greeter.log 2>&1 && pkill Hyprland"
    input {
      kb_layout = us,ru
      sensitivity = 0
      follow_mouse = 1
      accel_profile = flat
    }
    decoration {
      blur {
        enabled = no
      }
    }
    animations {
      enabled = no
    }
    misc {
      disable_hyprland_logo = true
      disable_splash_rendering = true
      disable_watchdog_warning = true
      background_color = 0x000000
      key_press_enables_dpms = true
      mouse_move_enables_dpms = true
    }
  '';

in
{
  config = lib.mkIf guiEnabled {
    services.greetd = {
      enable = true;
      restart = false;
      settings.default_session = {
        command = "${lib.getExe pkgs.hyprland} -c ${hyprlandConfig} > /dev/null 2>&1";
        user = "greeter";
      };
    };
    # Wait for input devices before starting greetd to avoid keyboard/mouse
    # not working during the first few seconds after greeter appears.
    systemd.services.greetd.preStart = ''
      while ! ls /dev/input/event* >/dev/null 2>&1; do
        sleep 0.2
      done
    '';
    # Prevent nix-maid's maid-activation.service from running for the greeter user.
    # The greeter runs a minimal Hyprland+quickshell session and does not need
    # user config management (tmpfiles, sd-switch, nix-store). Adding
    # ConditionUser=!greeter skips the service on greeter login, avoiding
    # unnecessary nix-store calls that delay greeter start.
    systemd.user.services.maid-activation.unitConfig.ConditionUser = "!greeter";
    security.pam.services.greetd.enableGnomeKeyring = true;
    users.users.greeter = {
      home = "/home/greeter";
      createHome = true;
      homeMode = "0710";
      isSystemUser = true;
      group = "greeter";
    };
    users.groups.greeter = { };
    # NB: quickshell for the greeter is NOT installed system-wide — the
    # greeter runs it via an absolute path (exec-once above). The global
    # `quickshell` binary comes from the nix-maid wrapper (single source).
    environment.etc."greetd/quickshell".source = config.lib.neg.path "files/quickshell";
    environment.etc."greetd/session-wrapper".source = pkgs.writeScript "session-wrapper" ''
      #!/bin/sh
      # Give the previous compositor time to release DRM master after greetd
      # transitions from the greeter session to the user session.
      # Atomic KMS is required for HDR metadata (hdr_output_metadata only works
      # through atomic commits; the legacy interface has no HDR support).
      # If atomic KMS misbehaves on RDNA4, investigate before re-enabling
      # AQ_NO_ATOMIC — it silently disables HDR.
      # export AQ_NO_ATOMIC=1
      exec /run/current-system/sw/bin/start-hyprland > /tmp/hyprland-debug.log 2>&1
    '';
    systemd.tmpfiles.rules = lib.mkAfter [
      "d /home/greeter 0710 greeter greeter -"
      "d /home/greeter/.cache 0775 greeter greeter -"
      "d /home/greeter/.config/quickshell 0755 greeter greeter -"
      "d /home/greeter/.config/quickshell/Theme 0755 greeter greeter -"
    ];
    system.activationScripts.greetdWallpaper =
      let
        jq = lib.getExe' pkgs.jq "jq";
      in
      ''
        WALLPAPER_SRC=""

        # Source 1: quickshell wallpaper path file (most up-to-date)
        qs_notify="${mainHome}/.cache/quickshell-wallpaper-path"
        if [ -f "$qs_notify" ]; then
          candidate="$(head -1 "$qs_notify" 2>/dev/null || true)"
          if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            WALLPAPER_SRC="$candidate"
          fi
        fi

        # Source 2: wl daemon state (current wallpaper from last session)
        if [ -z "$WALLPAPER_SRC" ]; then
          wl_state="${mainHome}/.local/state/wl/state.json"
          if [ -f "$wl_state" ]; then
            candidate="$(${jq} -r '.outputs | to_entries | .[0].value.wallpaper_path // empty' "$wl_state" 2>/dev/null || true)"
            if [ -n "$candidate" ] && [ -f "$candidate" ]; then
              WALLPAPER_SRC="$candidate"
            fi
          fi
        fi

        # Source 3: first image from the wl wallpaper directory
        if [ -z "$WALLPAPER_SRC" ]; then
          candidate="$(find ${mainHome}/pic/wl -maxdepth 1 -type f 2>/dev/null | sort -R | head -1 || true)"
          if [ -n "$candidate" ]; then
            WALLPAPER_SRC="$candidate"
          fi
        fi

        # Source 4: hardcoded fallback
        if [ -z "$WALLPAPER_SRC" ]; then
          WALLPAPER_SRC="${greeterWallpaperFallback}"
        fi

        if [ -f "$WALLPAPER_SRC" ]; then
          install -Dm644 -o greeter -g greeter "$WALLPAPER_SRC" "${greeterWallpaperDst}"
        else
          echo "greetd wallpaper: no source found (tried wl state, qs notify, pic/wl/, fallback)" >&2
        fi

        install -Dm644 -o greeter -g greeter ${pkgs.writeText "greeter-theme.json" "{}"} /home/greeter/.config/quickshell/Theme/.theme.json
      '';
  };
}
