{
  pkgs,
  lib,
  config,
  inputs,
  impurity,
  ...
}: let
  repoRoot = "/etc/nixos";
  quickshellSrc = "${repoRoot}/files/quickshell";

  # Feature flags check
  quickshellEnabled =
    config.features.gui.enable or false
    && config.features.gui.qt.enable or false
    && config.features.gui.quickshell.enable or false
    && !(config.features.devSpeed.enable or false);

  # Quickshell package from flake input
  qsPkg = pkgs.quickshell;

  # Wrapper factory
  mkQuickshellWrapper = import (inputs.self + "/lib/quickshell-wrapper.nix") {
    inherit lib pkgs;
  };

  # Wrapped quickshell package
  quickshellWrapped = mkQuickshellWrapper {
    inherit qsPkg;
    extraPath = [
      pkgs.fd
      pkgs.coreutils
      pkgs.bash
      pkgs.socat
      pkgs.iproute2
      pkgs.iputils
      pkgs.dash
      pkgs.ffmpeg
      pkgs.mpc
      pkgs.hyprland
      pkgs.neg.rsmetrx
    ];
  };

  # Theme builder script
  buildTheme = pkgs.writeShellApplication {
    name = "quickshell-build-theme";
    runtimeInputs = [pkgs.coreutils pkgs.nodejs_24 pkgs.systemd];
    text = ''
      set -euo pipefail
      # For mutable config, we build theme directly in the impurity source if valid,
      # or formatted output to ~/.config/quickshell/Theme/.theme.json
      # Actually, since we are linking, we can run this against the linked path.

      confdir="$HOME/.config/quickshell/Theme"
      mkdir -p "$confdir"
      # The build script presumably writes to --out
      ${pkgs.nodejs_24}/bin/node "$HOME"/.config/quickshell/Tools/build-theme.mjs --out "$confdir/.theme.json" --quiet
    '';
  };
in
  lib.mkIf quickshellEnabled {
    # Link Quickshell config mutably
    users.users.neg.maid.file.home.".config/quickshell".source = impurity.link quickshellSrc;

    # Wrapped quickshell package
    environment.systemPackages = [
      quickshellWrapped # Wrapped Quickshell with dependencies and environment
    ];

    # Quickshell panel service
    systemd.user.services.quickshell = {
      enable = true;
      description = "Quickshell - QtQuick based shell for Wayland";
      documentation = ["https://github.com/outfoxxed/quickshell"];
      partOf = ["graphical-session.target"];
      after = ["graphical-session-pre.target"];
      wantedBy = ["graphical-session.target"];
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
      partOf = ["graphical-session.target"];
      after = ["graphical-session-pre.target"];
      wantedBy = ["graphical-session.target"];
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
