{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  repoRoot = "/etc/nixos";
  quickshellSrc = "${repoRoot}/home/files/quickshell";

  # Feature flags check
  quickshellEnabled =
    config.features.gui.enable or false
    && config.features.gui.qt.enable or false
    && config.features.gui.quickshell.enable or false
    && !(config.features.devSpeed.enable or false);

  # Quickshell package from flake input
  qsPkg = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Qt paths for wrapper
  qsBin = lib.getExe' qsPkg "qs";
  qsQmlPath = "${qsPkg}/${pkgs.qt6.qtbase.qtQmlPrefix}";
  qsPath = pkgs.lib.makeBinPath [pkgs.fd pkgs.coreutils];

  # Wrapped quickshell package
  quickshellWrapped = pkgs.stdenv.mkDerivation {
    name = "quickshell-wrapped";
    buildInputs = [pkgs.makeWrapper];
    dontUnpack = true;
    installPhase = ''
      mkdir -p "$out/bin"
      makeWrapper ${qsBin} "$out/bin/qs" \
        --prefix QT_PLUGIN_PATH : "${pkgs.qt6.qtbase}/${pkgs.qt6.qtbase.qtPluginPrefix}" \
        --prefix QT_PLUGIN_PATH : "${pkgs.qt6.qt5compat}/${pkgs.qt6.qtbase.qtPluginPrefix}" \
        --prefix QT_PLUGIN_PATH : "${pkgs.kdePackages.qtwayland}/${pkgs.qt6.qtbase.qtPluginPrefix}" \
        --prefix QT_PLUGIN_PATH : "${pkgs.qt6.qtsvg}/${pkgs.qt6.qtbase.qtPluginPrefix}" \
        --prefix QML2_IMPORT_PATH : "${pkgs.qt6.qt5compat}/${pkgs.qt6.qtbase.qtQmlPrefix}" \
        --prefix QML2_IMPORT_PATH : "${pkgs.qt6.qtdeclarative}/${pkgs.qt6.qtbase.qtQmlPrefix}" \
        --prefix QML2_IMPORT_PATH : "${pkgs.qt6.qtpositioning}/${pkgs.qt6.qtbase.qtQmlPrefix}" \
        --prefix QML2_IMPORT_PATH : "${pkgs.qt6.qtsvg}/${pkgs.qt6.qtbase.qtQmlPrefix}" \
        --prefix QML2_IMPORT_PATH : "${pkgs.kdePackages.syntax-highlighting}/${pkgs.qt6.qtbase.qtQmlPrefix}" \
        --prefix QT_PLUGIN_PATH : "${pkgs.qt6.qtmultimedia}/${pkgs.qt6.qtbase.qtPluginPrefix}" \
        --prefix QML2_IMPORT_PATH : "${pkgs.qt6.qtmultimedia}/${pkgs.qt6.qtbase.qtQmlPrefix}" \
        --prefix QML2_IMPORT_PATH : "${qsQmlPath}" \
        --set QT_QPA_PLATFORM wayland \
        --set QML_XHR_ALLOW_FILE_READ 1 \
        --prefix PATH : ${qsPath}
    '';
    meta.mainProgram = "qs";
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
      if systemctl --user is-active -q quickshell.service; then
        systemctl --user restart quickshell.service >/dev/null 2>&1 || true
      fi
    '';
  };
in
  lib.mkIf quickshellEnabled {
    # Quickshell config symlink
    users.users.neg.maid.file.home = {
      ".config/quickshell".source = quickshellSrc;
    };

    # Wrapped quickshell package
    environment.systemPackages = [quickshellWrapped];

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
