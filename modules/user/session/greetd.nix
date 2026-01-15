{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  hyprlandPackage = pkgs.hyprland; # Dynamic tiling Wayland compositor that doesn't sacrifice ...
  mainUser = config.users.main.name or "neg";
  mainHome =
    if builtins.hasAttr mainUser config.users.users then
      config.users.users.${mainUser}.home or "/home/${mainUser}"
    else
      "/home/${mainUser}";
  greeterWallpaperSrc = "${mainHome}/pic/wl/waterfall_jungle_dark_150290_3840x2400.jpg";
  greeterWallpaperDst = "/var/lib/greetd/wallpaper.jpg";
  hyprlandConfig = pkgs.writeText "greetd-hyprland-config" ''
    # Monitor configuration — must match main session for correct HiDPI scaling
    monitorv2 {
      output = DP-2
      mode = 3840x2160@240
      position = 0x0
      scale = 1
    }

    # Disable phantom DP-1 (kernel reports only 640x480)
    monitorv2 {
      output = DP-1
      disabled = true
    }

    # For some reason pkill is way faster than dispatching exit, to the point greetd thinks the greeter died.
    exec-once = ${lib.getExe pkgs.bash} -c "QML2_IMPORT_PATH=/etc/greetd/quickshell ${
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
      background_color = 0x000000
      key_press_enables_dpms = true
      mouse_move_enables_dpms = true
    }
  '';
in
{
  services.greetd = {
    enable = true;
    restart = false;
    settings.default_session = {
      command = "${lib.getExe hyprlandPackage} -c ${hyprlandConfig}";
      user = "greeter";
    };
  };

  # Unlock GPG keyring on login
  security.pam.services.greetd.enableGnomeKeyring = true;

  # needed for hyprland cache dir
  users.users.greeter = {
    home = "/home/greeter";
    createHome = true;
    isSystemUser = true;
    group = "greeter";
  };
  users.groups.greeter = { };

  # Install QuickShell globally for the greeter
  environment.systemPackages = [
    inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  # Deploy QuickShell config to /etc instead of user profile
  environment.etc."greetd/quickshell".source = ../../../files/quickshell;

  # Wrapper for verifying session launch
  environment.etc."greetd/session-wrapper".source = pkgs.writeScript "session-wrapper" ''
    #!/bin/sh
    exec /run/current-system/sw/bin/hyprland > /tmp/hyprland-debug.log 2>&1
  '';

  # Keep the greeter wallpaper in a world-readable location; falls back to the bundled
  # background if the source is missing.
  systemd.tmpfiles.rules = lib.mkAfter [
    "d /var/lib/greetd 0755 root root -"
  ];

  system.activationScripts.greetdWallpaper = ''
    if [ -f "${greeterWallpaperSrc}" ]; then
      install -Dm644 "${greeterWallpaperSrc}" "${greeterWallpaperDst}"
    else
      echo "greetd wallpaper missing: ${greeterWallpaperSrc}" >&2
    fi
  '';
}
