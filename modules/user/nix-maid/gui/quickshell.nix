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
      pkgs.hyprland # dynamic tiling Wayland compositor
      pkgs.neg.rsmetrx # custom metrics exporter
    ];
  };

  # Theme builder script
  buildTheme = pkgs.writeShellApplication {
    name = "quickshell-build-theme";
    runtimeInputs = [
      pkgs.coreutils # basic file operations
      pkgs.nodejs_24 # javascript runtime for build script
      pkgs.systemd # systemd utilities
    ];
    text = ''
      set -euo pipefail
      # For mutable config, we build theme directly in the impurity source if valid,
      # or formatted output to ~/.config/quickshell/Theme/.theme.json
      # Actually, since we are linking, we can run this against the linked path.

      confdir="$HOME/.config/quickshell/Theme"
      mkdir -p "$confdir"
      # The build script presumably writes to --out
      ${pkgs.nodejs_24}/bin/node "$HOME"/.config/quickshell/Tools/build-theme.mjs --dir "$confdir" --out "$confdir/.theme.json" --quiet # Event-driven I/O framework for the V8 JavaScript engine
    '';
  };
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

      # Theme watch service
      systemd.user.services.quickshell-theme-watch = {
        enable = true;
        description = "Watch Quickshell theme tokens";
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session-pre.target" ];
        wantedBy = [ "graphical-session.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStartPre = lib.getExe buildTheme;
          ExecStart = ''
            ${pkgs.watchexec}/bin/watchexec \
              --restart \
              --watch %h/.config/quickshell/Theme \
              --watch %h/.config/quickshell/Theme/manifest.json \
              --exts json,jsonc \
              --ignore %h/.config/quickshell/Theme/.theme.json \
              --debounce 250ms \
              -- ${lib.getExe buildTheme}
          '';
          Restart = "on-failure";
          RestartSec = 2;
        };
      };
    }

    (n.mkHomeFiles {
      # Link Quickshell config mutably via impurity
      ".config/quickshell".source = n.linkImpure quickshellSrc;
    })
  ]
)
