{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  hyprlandPackage = pkgs.hyprland;
  mainUser = config.users.main.name or "neg";
  mainHome =
    if builtins.hasAttr mainUser config.users.users
    then config.users.users.${mainUser}.home or "/home/${mainUser}"
    else "/home/${mainUser}";
  greeterWallpaperSrc = "${mainHome}/pic/wl/waterfall_jungle_dark_150290_3840x2400.jpg";
  greeterWallpaperDst = "/var/lib/greetd/wallpaper.jpg";
  hyprlandConfig = pkgs.writeText "greetd-hyprland-config" ''
    # for some reason pkill is way faster than dispatching exit, to the point greetd thinks the greeter died.
    exec-once = quickshell -p /etc/greetd/quickshell/greeter.qml >& qslog.txt && pkill Hyprland

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
in {
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
  users.groups.greeter = {};

  # Install QuickShell globally for the greeter
  environment.systemPackages = [
    inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  # Deploy QuickShell config to /etc instead of Home Manager
  environment.etc."greetd/quickshell".source = ../../../files/quickshell;

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
