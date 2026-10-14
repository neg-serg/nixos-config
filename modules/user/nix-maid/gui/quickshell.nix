{
  pkgs,
  lib,
  config,
  neg,
  inputs,
  ...
}:
let
  # Module-shaped systemd user units (lib/systemd-user.nix)
  systemdUser = config.lib.neg.systemdUser;

  # Source path
  quickshellSrc = config.lib.neg.path "files/quickshell";
  # live links for the deployed tree; the package build below keeps the store copy
  quickshellSrcLive = config.lib.neg.live "files/quickshell";

  # Feature flags check (single source: config.lib.neg.quickshellEnabled)
  quickshellEnabled = config.lib.neg.quickshellEnabled;

  # Quickshell package from the pinned flake input (post-v0.3.0 crash fixes),
  # same source the greeter already uses; nixpkgs' v0.3.0 tag lacks them.
  qsPkg = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Wrapper factory
  mkQuickshellWrapper = import (config.lib.neg.path "lib/quickshell-wrapper.nix") {
    inherit lib pkgs;
  };

  # Wrapped quickshell package
  quickshellWrapped = mkQuickshellWrapper {
    inherit qsPkg;
    extraPath = [
      pkgs.coreutils # basic file, shell and text manipulation utilities
      pkgs.bash # GNU Bourne-Again Shell
      pkgs.socat # multipurpose relay (SOcket CAT)
      pkgs.iproute2 # networking utilities
      pkgs.iputils # basic networking tool suite (ping, traceroute, etc.)
      pkgs.dash # POSIX-compliant shell
      pkgs.ffmpeg # multimedia framework
      pkgs.mpc # client for MPD
      pkgs.gawk # GNU awk: used by SystemMonitor probes parsing /proc/{meminfo,swaps,diskstats}
      pkgs.hyprland # dynamic tiling Wayland compositor
      pkgs.neg.rsmetrx # custom metrics exporter
      pkgs.khal # CLI calendar (used by CalendarEvents.js for khal list)
    ];
  };

  # Pre-start init: deploy writable config directories before quickshell starts.
  # Theme, Settings — copy-once so user edits persist.
  # Components, Bar — force-copied on every start so dev edits under
  # /etc/nixos/files/quickshell/ take effect immediately.
  quickshellPreStart = pkgs.writeShellScript "quickshell-pre-start" (
    builtins.readFile (
      pkgs.replaceVars ./quickshell/pre-start.sh {
        quickshellSrc = pkgs.copyPathToStore quickshellSrc;
      }
    )
  );

  # Hang watchdog probe (quickshell-health.timer runs it every 2 minutes).
  # `Restart=on-failure` covers a shell that crashes; it does nothing for one
  # that keeps running with a dead event loop. 2026-10-13 was exactly that: the
  # IPC socket stopped answering while the unit stayed "active", and because
  # quickshell owns the org.freedesktop.Notifications name, notify-send went to
  # `Timeout was reached` — screenrec notifies *before* it starts wf-recorder, so
  # `set -e` killed it and the recording hotkey looked broken. One IPC round-trip
  # is the liveness test; the age guard keeps a shell that is merely starting up
  # from being restarted under itself.
  quickshellHealth = pkgs.writeShellScript "quickshell-health" ''
    set -uo pipefail

    # A stopped or crashed shell is not this probe's business: restartOnFailure
    # owns that path, and the login-phase condition keeps the bar down on purpose.
    [ "$(systemctl --user is-active quickshell.service 2>/dev/null || true)" = "active" ] || exit 0

    if timeout 5 quickshell ipc show >/dev/null 2>&1; then
      exit 0
    fi

    # Only an instance that has been up for a while can be called wedged: a shell
    # that is still starting (or one that just restarted) answers late.
    active_us="$(systemctl --user show -p ActiveEnterTimestampMonotonic --value quickshell.service 2>/dev/null || true)"
    active_us="''${active_us:-0}"
    case "$active_us" in
      *[!0-9]*) exit 0 ;;
    esac
    [ "$active_us" -gt 0 ] || exit 0

    uptime_s="$(cut -d. -f1 /proc/uptime)"
    active_s=$((active_us / 1000000))
    [ $((uptime_s - active_s)) -ge 90 ] || exit 0

    systemctl --user restart quickshell.service
  '';

  # Build individual nix-maid entries for source dir top-level contents,
  # excluding writable paths (Theme, Settings, Settings.json, .github)
  # and force-copied paths (Components, Bar, Helpers, Notifications,
  # art, shaders).
  quickshellSrcEntries = builtins.readDir quickshellSrc;

  quickshellSrcNames = builtins.filter (
    name:
    name != "Theme"
    && name != "theme"
    && name != ".github"
    && name != "Settings.json"
    && name != "Settings"
    && name != "Components"
    && name != "Bar"
    && name != "Helpers"
    && name != "Notifications"
    && name != "Widgets"
    && name != "art"
    && name != "shaders"
  ) (builtins.attrNames quickshellSrcEntries);

  quickshellHomeFiles = neg.mkDirLinks ".config/quickshell" quickshellSrcLive quickshellSrcNames;
in
lib.mkIf quickshellEnabled (
  lib.mkMerge [
    {
      # Wrapped quickshell package
      environment.systemPackages = [
        quickshellWrapped # Wrapped Quickshell with dependencies and environment
      ];

      # Quickshell panel service — ExecStartPre deploys writable config before start
      systemd.user.services.quickshell = systemdUser.mkUserService {
        enable = true;
        description = "Quickshell - QtQuick based shell for Wayland";
        documentation = [ "https://github.com/outfoxxed/quickshell" ];
        presets = [ "restartOnFailure" ];
        partOf = [ "hyprland-session.target" ];
        unitConfig = {
          StartLimitIntervalSec = 30;
          StartLimitBurst = 5;
          # Refuse to start while the login screen is up. The bar belongs to the
          # session, and hyprland.lua's login branch starts nothing of the session
          # — but that intent is not enough on its own: nix-maid's sd-switch starts
          # changed units *directly*, bypassing the session target, and on
          # 2026-09-19 18:25:47 it brought the bar up behind the login screen's
          # lock surface. hypr-start then killed and restarted it right after the
          # password (PartOf=hyprland-session.target), i.e. ~5 s of shell work and
          # a visible blink. The marker is removed when the password is accepted
          # (greeter/login.qml + hypr-start), and the condition is re-evaluated
          # then, so the shell still starts with the session target.
          ConditionPathExists = "!%t/quickshell-login/login-phase";
        };

        after = [
          "graphical-session-pre.target"
          "pipewire.service"
        ];
        wants = [ "pipewire.service" ];
        wantedBy = [ "hyprland-session.target" ];
        serviceConfig = {
          ExecStartPre = "${quickshellPreStart}";
          ExecStart = "${lib.getExe quickshellWrapped} -p %h/.config/quickshell/shell.qml";
          # A startup crash (~1-3 s cycle) previously looped forever: the default
          # StartLimitBurst=5/10s never trips at this cadence (NRestarts hit 198).
          # Back off and stop after 5 quick failures in 30 s.
          RestartSec = 5;
          # Resource ceilings. Measured 2026-10-14: the shell is flat, not
          # leaking — 264-282 MB VmRSS over a 15 min window, ~181 MB cgroup
          # current and 203 MB cgroup peak here (251 MB peak over an 11 min
          # session), ~2-3 % CPU (12.4 s over 8 min). The idle work is the five
          # unconditional tick timers in Services/Timers.qml plus event
          # handling, not a leak. The caps sit 2-3x above the measured numbers,
          # so normal use never touches them: MemoryHigh throttles a runaway
          # allocation (e.g. a huge wallpaper or a cover loop) before it
          # pressures the desktop, MemoryMax kills and the restart policy brings
          # the bar back, and CPUQuota bounds a busy loop without touching
          # normal animation work (two cores is far above what the shell uses).
          MemoryHigh = "384M";
          MemoryMax = "768M";
          CPUQuota = "200%";
          Environment = [
            "QML_XHR_ALLOW_FILE_WRITE=1"
            # ~/.local/bin first: the Genelec widget shells out to glm-vol, which
            # owns the runtime volume file ($XDG_RUNTIME_DIR/genlc-volume) that
            # genlc-media and glm-vol read back. Without it on PATH that call
            # failed silently, the file stayed at whatever `touch` created, and
            # every fresh session fell back to the hardcoded -40 dB.
            "PATH=%h/.local/bin:/run/current-system/sw/bin:\${PATH}"
          ];
        };
      };

      # Hang watchdog (probe: quickshellHealth above). `restartOnFailure` only
      # reacts to a shell that *exits*; a shell that is "active" while its event
      # loop is dead is invisible to systemd — and it takes the notification
      # service down with it. One IPC round-trip every 2 minutes is the whole
      # price of noticing.
      systemd.user.services.quickshell-health = systemdUser.mkUserService {
        description = "Restart the Quickshell shell when it stops answering its IPC";
        presets = [ "oneshot" ];
        # User units start with a minimal PATH: the probe needs the shell's own
        # CLI plus timeout/systemctl/cut.
        path = [
          pkgs.coreutils # timeout and cut, used by the probe
          pkgs.systemd # systemctl --user: the liveness check and the restart
          quickshellWrapped # the shell's own CLI for `quickshell ipc`
        ];
        serviceConfig = {
          ExecStart = quickshellHealth;
        };
      };

      systemd.user.timers.quickshell-health = {
        description = "Timer: Quickshell hang watchdog";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5m";
          OnUnitActiveSec = "2m";
        };
      };
    }

    (neg.mkHomeFiles quickshellHomeFiles)
    {
      # Remove old quickshell symlinks before nix-maid activation deploys new ones.
      # Only deletes symlinks — preserves writable dirs (Theme, Settings)
      # and writable files (Settings.json) created by ExecStartPre.
      systemd.user.services.quickshell-cleanup-symlink = {
        description = "Remove old quickshell symlinks before nix-maid activation";
        before = [ "maid-activation.service" ];
        wantedBy = [ "maid-activation.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "quickshell-cleanup-symlink" ''
            qs="$HOME/.config/quickshell"
            if [ -L "$qs" ]; then
              rm -f "$qs" 2>/dev/null || true
            elif [ -d "$qs" ]; then
              find "$qs" -maxdepth 1 -type l -delete 2>/dev/null || true
            fi
            rm -rf "$HOME/.local/state/nix-maid/static/.config/quickshell" 2>/dev/null || true
          '';
        };
      };
    }
    {
      systemd.user.services.quickshell.after = lib.mkForce [
        "graphical-session-pre.target"
        "maid-activation.service"
        "pipewire.service"
      ];
      systemd.user.services.quickshell.wants = [ "maid-activation.service" ];
    }
  ]
)
