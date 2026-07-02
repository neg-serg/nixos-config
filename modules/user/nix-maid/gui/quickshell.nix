{
  pkgs,
  lib,
  config,
  inputs,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  # Source path (Nix path for linkImpure)
  quickshellSrc = ../../../../files/quickshell;

  # Feature flags check
  quickshellEnabled =
    config.features.gui.enable or false
    && config.features.gui.qt.enable or false
    && config.features.gui.quickshell.enable or false
    && !(config.features.devSpeed.enable or false);

  # Quickshell package from flake input
  qsPkg = pkgs.quickshell; # Flexbile QtQuick based desktop shell toolkit

  # Wrapper factory
  mkQuickshellWrapper = import (inputs.self + "/lib/quickshell-wrapper.nix") {
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
    ];
  };

  # Theme init: copy read-only Theme symlink to writable cache dir before quickshell starts.
  # Runs as a user oneshot (so files are owned by the user, not root).
  quickshellThemeInitScript = pkgs.writeShellScript "quickshell-theme-init" ''
    theme_dir="$HOME/.config/quickshell/Theme"
    cache_dir="$HOME/.cache/quickshell-theme"
    if [ -L "$theme_dir" ] && [ ! -w "$theme_dir" ]; then
      mkdir -p "$cache_dir"
      if [ -z "$(ls -A "$cache_dir" 2>/dev/null)" ]; then
        cp -r "$theme_dir"/* "$cache_dir"/ 2>/dev/null || true
      fi
      rm -f "$theme_dir"
      ln -sf "$cache_dir" "$theme_dir"
    fi
  '';
in
lib.mkIf quickshellEnabled (
  lib.mkMerge [
    {
      # Wrapped quickshell package
      environment.systemPackages = [
        quickshellWrapped # Wrapped Quickshell with dependencies and environment
      ];

      # Quickshell panel service
      systemd.user.services.quickshell = {
        enable = true;
        description = "Quickshell - QtQuick based shell for Wayland";
        documentation = [ "https://github.com/outfoxxed/quickshell" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session-pre.target" ];
        wantedBy = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${lib.getExe quickshellWrapped} -p %h/.config/quickshell/shell.qml";
          Restart = "on-failure";
          RestartSec = 1;
        };
      };
    }

    (n.mkHomeFiles {
      # Link Quickshell config mutably via impurity
      ".config/quickshell".source = n.linkImpure quickshellSrc;
    })
    {
      systemd.user.services.quickshell-theme-init = {
        description = "Copy read-only Theme to writable cache dir before quickshell starts";
        after = [ "maid-activation.service" ];
        before = [ "quickshell.service" ];
        requiredBy = [ "quickshell.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe' quickshellThemeInitScript "quickshell-theme-init"}";
        };
      };

      systemd.user.services.quickshell.after = lib.mkForce [ "graphical-session-pre.target" "maid-activation.service" ];
      systemd.user.services.quickshell.wants = [ "maid-activation.service" ];
    }
  ]
)
