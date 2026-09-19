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
  inherit (config.lib.neg) mainUser;
  greeterCache = "/home/greeter/.cache";
  greeterWallpaperDst = "${greeterCache}/greeter-wallpaper";
  # Fallback when no dynamic source yields a file at activation time.
  greeterWallpaperFallback = "${mainHome}/pic/wl/waterfall_jungle_dark_150290_3840x2400.jpg";
  # The interactive login is no longer a greeter session: greetd runs this
  # wrapper as the main user and the compositor it starts paints the login
  # screen itself (files/quickshell/greeter/login.qml, login phase in
  # files/gui/hypr/hyprland.lua). See session-wrapper.sh for the marker that
  # separates the two phases.
  sessionWrapper = pkgs.writeScript "session-wrapper" (builtins.readFile ./greetd/session-wrapper.sh);
  # Called from hyprland.lua during the login phase; the tree it loads is
  # deployed at /etc/quickshell below.
  loginLayer = pkgs.writeShellScriptBin "qs-login-layer" (builtins.readFile ./greetd/login-layer.sh);
  # Old greeter session config: kept, but nothing starts it any more — see
  # settings.default_session. It is the fallback if the single-compositor login
  # has to be reverted (point default_session back at it).
  greetdHyprlandConfig = pkgs.replaceVars (config.lib.neg.path "files/gui/hypr/greetd.lua") {
    quickshell = lib.getExe inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };

in
{
  config = lib.mkIf guiEnabled {
    services.greetd = {
      enable = true;
      restart = false;
      # Single-compositor login: this *is* the session — no greeter process, no
      # second compositor, no DRM mode re-set on login.
      #
      # greetd starts the default session whenever no session is running, so
      # after a logout (the compositor exits, i.e. the default session exits) it
      # comes straight back here and the login screen returns. The wrapper runs
      # as the main user through greetd's PAM stack, which is what creates the
      # logind session, /run/user/$UID and the user systemd instance the
      # desktop's `systemctl --user start hyprland-session.target` needs.
      #
      # No authentication happens here (greetd has no one to ask): the session
      # starts and the login layer in it asks for the password. The old greeter
      # config is kept in `greetdHyprlandConfig` for a revert.
      settings.default_session = {
        command = "${sessionWrapper}";
        user = mainUser;
      };
    };
    # NixOS ships greetd as Type=idle, which makes systemd defer the spawn of
    # the service binary until all jobs are dispatched. On odin that placed the
    # greetd process ~6s after the unit was already marked active (2026-09-15
    # boot: ActiveEnter 8.52s, ExecMainStart 14.53s — the only unit on the host
    # with such a gap), delaying the login prompt by the same amount. greetd is
    # an ordinary long-running foreground daemon; upstream's own unit uses
    # Type=simple.
    # mkForce: the nixpkgs greetd module hardcodes Type=idle on this unit.
    systemd.services.greetd.serviceConfig.Type = lib.mkForce "simple";
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
    # The login layer (started by hyprland.lua in the login phase) loads the tree
    # from /etc/quickshell: that phase runs before the session target, so
    # ~/.config/quickshell — nix-maid's symlink farm — is not guaranteed to be
    # deployed yet, and a login screen that depends on it could not be trusted.
    # `quickshell` itself comes from the nix-maid wrapper (single source), so the
    # layer needs no absolute path.
    environment.etc."quickshell".source = config.lib.neg.path "files/quickshell";
    environment.systemPackages = [ loginLayer ];
    # Kept for the greeter fallback (greetdHyprlandConfig / greetd.lua): the old
    # greeter reads its quickshell tree and its session launcher from /etc/greetd.
    # Nothing starts that session any more — see settings.default_session.
    environment.etc."greetd/quickshell".source = config.lib.neg.path "files/quickshell";
    environment.etc."greetd/session-wrapper".source = sessionWrapper;
    # …and the old greeter's compositor config, so reverting is a one-line change
    # (point default_session back at `${lib.getExe pkgs.hyprland} -c /etc/greetd/greetd-hyprland-config.lua`
    # with user = "greeter").
    environment.etc."greetd/greetd-hyprland-config.lua".source = greetdHyprlandConfig;
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
