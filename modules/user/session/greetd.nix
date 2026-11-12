{
  config,
  lib,
  pkgs,
  ...
}:
let
  guiEnabled = config.features.gui.enable or true;
  inherit (config.lib.neg) mainUser;
  # The interactive login is no longer a greeter session: greetd runs this
  # wrapper as the main user and the compositor it starts paints the login
  # screen itself (the pleamar lock scene, files/pleamar/shells/lock/lock.plm,
  # from the login phase in files/gui/hypr/hyprland.lua). See session-wrapper.sh
  # for the marker that separates the two phases.
  sessionWrapper = pkgs.writeScript "session-wrapper" (builtins.readFile ./greetd/session-wrapper.sh);
  # The pleamar tree the login layer loads the lock scene from. A store copy on
  # purpose: during the login phase the session target has not started and
  # nix-maid has not linked ~/.config/pleamar yet, so a scene read from the home
  # directory could not be trusted to exist. files/pleamar is the whole import
  # root (`shells/lock/lock.plm` imports ../../lib/*.plm, and the committed
  # theme.plm sits at the root), so the copy is the tree, not one directory of it.
  pleamarLoginTree = config.lib.neg.path "files/pleamar";
  # The lock scene spawns its keyboard worker by name
  # (`permissions { run: "pleamar-kbdlayout" }`): ~/.local/bin, where nix-maid
  # puts it for the session, is not there yet at login, so the compiled worker
  # is carried in the store under the name the scene asks for.
  pleamarLoginHelpers = pkgs.runCommand "pleamar-login-helpers" { } ''
    mkdir -p $out/bin
    ln -s ${lib.getExe pkgs.neg.pleamar-kbdlayout} $out/bin/pleamar-kbdlayout
  '';
  # Called from hyprland.lua during the login phase; it launches the pleamar lock
  # scene (files/pleamar/shells/lock/lock.plm) from the tree deployed at
  # /etc/pleamar-lock below. The handover contract it relies on — `pleamar --say
  # lock "wait unlocked == true"`, the "session" marker, the lock release and the
  # `lock.held` guard — is described at the top of the script.
  loginLayer = pkgs.writeShellScriptBin "pleamar-login-layer" (
    builtins.readFile (
      pkgs.replaceVars ./greetd/login-layer.sh {
        pleamar = lib.getExe pkgs.pleamar;
        jq = lib.getExe' pkgs.jq "jq";
        pleamarTree = "/etc/pleamar-lock";
        kbdHelpers = pleamarLoginHelpers;
      }
    )
  );

in
{
  config = lib.mkIf guiEnabled {
    services.greetd = {
      enable = true;
      # A failed session start must not cost the login: the wrapper exits with
      # the compositor, greetd ends with "greeter exited without creating a
      # session" and, with Restart=no, nothing brings the login screen back.
      # That is what happened on the 2026-11-12 boot — Aquamarine could not
      # activate the logind session (bootvine had taken the console), Hyprland
      # aborted and the host stayed on a text console. `restart = true` gives
      # greetd another attempt (nixpkgs renders it as Restart=on-success, which
      # is the path a failed session takes: greetd exits 0); the start limit
      # below keeps a persistent failure from respawning it forever.
      restart = true;
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
      # starts and the login layer in it asks for the password. There is no
      # second greeter to fall back to any more: a broken login is undone with
      # the previous generation (or a `git revert` of the login wiring), not with
      # a config switch.
      settings.default_session = {
        command = "${sessionWrapper}";
        user = mainUser;
      };
    };
    # NixOS ships greetd as Type=idle, which makes systemd defer the spawn of
    # the service binary until all jobs are dispatched. On trantor that placed the
    # greetd process ~6s after the unit was already marked active (2026-09-15
    # boot: ActiveEnter 8.52s, ExecMainStart 14.53s — the only unit on the host
    # with such a gap), delaying the login prompt by the same amount. greetd is
    # an ordinary long-running foreground daemon; upstream's own unit uses
    # Type=simple.
    # mkForce: the nixpkgs greetd module hardcodes Type=idle on this unit.
    systemd.services.greetd.serviceConfig.Type = lib.mkForce "simple";
    # Pace and cap the restarts from the option above: one retry after bootvine
    # has yielded the console is the point, a compositor respawn every 100 ms is
    # not. After five attempts in five minutes systemd leaves greetd failed,
    # which is the honest state when the session itself is broken.
    systemd.services.greetd.serviceConfig.RestartSec = "5s";
    systemd.services.greetd.startLimitIntervalSec = 300;
    systemd.services.greetd.startLimitBurst = 5;
    # Wait for input devices before starting greetd to avoid keyboard/mouse
    # not working during the first few seconds after greeter appears.
    systemd.services.greetd.preStart = ''
      while ! ls /dev/input/event* >/dev/null 2>&1; do
        sleep 0.2
      done
      # bootvine owns tty12 and re-activates it every frame until its watcher
      # sees greetd's unit leave the inactive state — about 0.4 s after the
      # start job begins. greetd switches to its own VT ~30 ms after the main
      # process starts, so without a margin bootvine flips the console back to
      # tty12, the logind session never becomes active and Aquamarine's 5 s
      # wait for it expires (2026-11-12: Hyprland aborted with
      # CBackend::create() failed!, crash report 479). The delay puts greetd's
      # VT switch after bootvine's handover has begun; bootvine then sees the
      # console taken and leaves it alone.
      sleep 2
    '';
    security.pam.services.greetd.enableGnomeKeyring = true;
    # The lock scene checks the password through the PAM service `pleamar`
    # (files/pleamar/shells/lock/lock.luau → `sys.ask("auth.check", …)`), and
    # NixOS writes /etc/pam.d/pleamar only for a service somebody declared.
    # modules/user/nix-maid/gui/pleamar.nix declares it whenever the shell is on;
    # these mkDefaults keep the stack in place when that flag is off, because a
    # login screen whose password field has no PAM stack behind it is a lockout
    # and not a degraded mode. That module's own values win whenever it is on.
    security.pam.services.pleamar.unixAuth = lib.mkDefault true;
    security.pam.services.pleamar.fprintAuth = lib.mkDefault true;
    # No `greeter` account any more. It existed because the greeter session used to
    # run as its own user, which also needed the wallpaper copied into a home it
    # could read; on 2026-11-02 the login became a session-lock scene inside the
    # main user's compositor, and on 2026-11-03 the last readers of that copy went
    # away (modules/user/nix-maid/sys/wallpaper-sync.nix no longer writes it). The
    # old /home/greeter is left on disk: nothing owns it now, and deleting a home
    # is not a rebuild's decision.
    environment.systemPackages = [ loginLayer ];
    # The pleamar tree the login layer loads its scene from: a store copy, because
    # the login phase runs before the session target, so ~/.config/pleamar is not
    # guaranteed to be linked yet. Read by pleamar-login-layer, which prefers the
    # /etc/nixos checkout while it exists.
    #
    # This replaced both Quickshell deployments of the login screen
    # (environment.etc."quickshell" and the greeter fallback under /etc/greetd):
    # nothing reads the deleted legacy QML tree at login any more. That also ends the
    # theme copy modules/user/session/greetd/wallpaper.sh used to make — the login
    # phase now runs as the main user, whose own ~/.config/pleamar/theme.plm is the
    # live palette, and the tree here carries the committed files/pleamar/theme.plm
    # for the `import "../../theme.plm"` slot, so there is no second account to
    # copy a theme into.
    environment.etc."pleamar-lock".source = pleamarLoginTree;
    # The wrapper is deployed as a readable copy of what greetd runs; greetd itself
    # starts the store path above.
    environment.etc."greetd/session-wrapper".source = sessionWrapper;
    # No session list and no /usr/share/wayland-sessions: the old greeter read the
    # .desktop files there to offer a session choice, and this host has one user and
    # one session — the port dropped the selector (files/pleamar/docs/PARITY.md, the
    # "User and session selection" row). Nothing reads that directory now.
  };
}
