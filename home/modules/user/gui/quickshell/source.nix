{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  systemctl = lib.getExe' pkgs.systemd "systemctl";
  filesRoot = "${config.neg.hmConfigRoot}/files";
in
  mkIf (config.features.gui.enable && (config.features.gui.qt.enable or false) && (config.features.gui.quickshell.enable or false)) {
    home.activation.backupLegacyQuickshell = lib.hm.dag.entryBefore ["linkGeneration"] ''
      set -euo pipefail
      target="${config.xdg.configHome}/quickshell"
      if [ -e "$target" ] && [ ! -L "$target" ]; then
        backupRoot="${config.xdg.configHome}/hm-backup"
        mkdir -p "$backupRoot"
        dest="$backupRoot/quickshell.$(date +%s)"
        mv "$target" "$dest"
      fi
    '';
    home.file.".config/quickshell" = {
      recursive = true;
      source = filesRoot + "/quickshell/quickshell";
      force = true;
    };

    # After linking the updated config, restart quickshell if it is running.
    # Quickshell 0.2+ no longer supports SIGHUP reloads, so we bounce the service.
    home.activation.quickshell-reload = lib.hm.dag.entryAfter ["linkGeneration"] ''
      set -e
      if "${systemctl}" --user is-active -q quickshell.service; then
        "${systemctl}" --user restart quickshell.service || true
      fi
    '';
  }
