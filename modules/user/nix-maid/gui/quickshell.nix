{
  pkgs,
  lib,
  config,
  neg,
  inputs,
  ...
}:
let
  # Source path
  quickshellSrc = config.lib.neg.path "files/quickshell";

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

  quickshellHomeFiles = neg.mkDirLinks ".config/quickshell" quickshellSrc quickshellSrcNames;
in
lib.mkIf quickshellEnabled (
  lib.mkMerge [
    {
      # Wrapped quickshell package
      environment.systemPackages = [
        quickshellWrapped # Wrapped Quickshell with dependencies and environment
      ];

      # Quickshell panel service — ExecStartPre deploys writable config before start
      systemd.user.services.quickshell = {
        enable = true;
        description = "Quickshell - QtQuick based shell for Wayland";
        documentation = [ "https://github.com/outfoxxed/quickshell" ];
        partOf = [ "hyprland-session.target" ];
        unitConfig = {
          StartLimitIntervalSec = 30;
          StartLimitBurst = 5;
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
          Restart = "on-failure";
          # A startup crash (~1-3 s cycle) previously looped forever: the default
          # StartLimitBurst=5/10s never trips at this cadence (NRestarts hit 198).
          # Back off and stop after 5 quick failures in 30 s.
          RestartSec = 5;
          Environment = [
            "QML_XHR_ALLOW_FILE_WRITE=1"
            "PATH=/run/current-system/sw/bin:\${PATH}"
          ];
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
