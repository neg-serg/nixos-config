{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  guiEnabled = config.features.gui.enable or true;
  mainHome = config.lib.neg.homeDir;
  greeterCache = "/home/greeter/.cache";
  greeterWallpaperDst = "${greeterCache}/greeter-wallpaper";
  # Fallback when no dynamic source yields a file at activation time.
  greeterWallpaperFallback = "${mainHome}/pic/wl/waterfall_jungle_dark_150290_3840x2400.jpg";
  hyprlandConfig = pkgs.replaceVars (config.lib.neg.path "files/gui/hypr/greetd.lua") {
    quickshell = lib.getExe inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };

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
    environment.etc."greetd/session-wrapper".source = pkgs.writeScript "session-wrapper" (
      builtins.readFile ./greetd/session-wrapper.sh
    );
    # Expose wayland/x11 session .desktop files so the greeter can list and
    # switch sessions (Hyprland only).
    environment.pathsToLink = lib.mkAfter [
      "/share/wayland-sessions"
      "/share/xsessions"
    ];
    systemd.tmpfiles.rules = lib.mkAfter [
      # Greeter reads session .desktop files from /usr/share/wayland-sessions;
      # point it at the system profile's merged share dir.
      "d /usr/share 0755 root root -"
      "L+ /usr/share/wayland-sessions - - - - /run/current-system/sw/share/wayland-sessions"
      "L+ /usr/share/xsessions - - - - /run/current-system/sw/share/xsessions"
      "d /home/greeter 0710 greeter greeter -"
      "d /home/greeter/.cache 0775 greeter greeter -"
      "d /home/greeter/.config/quickshell 0755 greeter greeter -"
      "d /home/greeter/.config/quickshell/Theme 0755 greeter greeter -"
    ];
    system.activationScripts.greetdWallpaper =
      let
        jq = lib.getExe' pkgs.jq "jq";
      in
      builtins.readFile (
        pkgs.replaceVars ./greetd/wallpaper.sh {
          themeDir = pkgs.copyPathToStore (config.lib.neg.path "files/quickshell/Theme");
          inherit
            greeterWallpaperDst
            greeterWallpaperFallback
            jq
            mainHome
            ;
          gnused = pkgs.gnused;
        }
      );
  };
}
