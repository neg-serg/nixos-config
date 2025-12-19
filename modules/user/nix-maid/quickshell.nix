{
  pkgs,
  lib,
  config,
  inputs,
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
      cd ${quickshellSrc}
      # Write merged theme into the writable config dir, not the Nix store.
      confdir="$HOME/.config/quickshell/Theme"
      mkdir -p "$confdir"
      # Replace any symlinked .theme.json with a real file.
      rm -f "$confdir/.theme.json"
      ${pkgs.nodejs_24}/bin/node Tools/build-theme.mjs --out "$confdir/.theme.json" --quiet
    '';
  };

  # Sync script that copies quickshell config (mutable, not symlink)
  syncQuickshell = pkgs.writeShellApplication {
    name = "quickshell-sync-config";
    runtimeInputs = [pkgs.rsync pkgs.coreutils];
    text = ''
      set -euo pipefail
      src="${quickshellSrc}/"
      dest="$HOME/.config/quickshell/"
      mkdir -p "$dest"
      # Sync files, preserving any local changes to Theme/.theme.json
      rsync -a --delete \
        --exclude 'Theme/.theme.json' \
        --exclude '*.zwc' \
        "$src" "$dest"
    '';
  };
in
  lib.mkIf quickshellEnabled {
    # Wrapped quickshell package + sync script
    environment.systemPackages = [
      quickshellWrapped # Wrapped Quickshell with dependencies and environment
      syncQuickshell # Helper script to sync Quickshell config from repo to home
    ];

    # Quickshell config sync service (runs before quickshell starts)
    systemd.user.services.quickshell-sync = {
      enable = true;
      description = "Sync Quickshell config from repo";
      partOf = ["graphical-session.target"];
      before = ["quickshell.service" "quickshell-theme-watch.service"];
      wantedBy = ["graphical-session.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe syncQuickshell;
        RemainAfterExit = true;
      };
    };

    # Quickshell panel service
    systemd.user.services.quickshell = {
      enable = true;
      description = "Quickshell - QtQuick based shell for Wayland";
      documentation = ["https://github.com/outfoxxed/quickshell"];
      partOf = ["graphical-session.target"];
      after = ["graphical-session-pre.target" "quickshell-sync.service"];
      requires = ["quickshell-sync.service"];
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
            --watch ${quickshellSrc}/Theme \
            --watch ${quickshellSrc}/Theme/manifest.json \
            --exts json,jsonc \
            --ignore ${quickshellSrc}/Theme/.theme.json \
            --debounce 250ms \
            -- ${lib.getExe buildTheme}
        '';
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  }
