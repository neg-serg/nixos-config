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
    home.file.".config/quickshell" = {
      recursive = true;
      source = filesRoot + "/quickshell";
      force = true;
    };

    # After linking the updated config, restart quickshell if it is running.
    # We also restart quickshell-theme-watch to ensure the .theme.json is correctly re-generated
    # (since the link step might have overwritten it with the symlink).
    home.activation.quickshell-reload = lib.hm.dag.entryAfter ["linkGeneration"] ''
      set -e
      if "${systemctl}" --user is-active -q quickshell-theme-watch.service; then
        "${systemctl}" --user restart quickshell-theme-watch.service || true
      fi
      if "${systemctl}" --user is-active -q quickshell.service; then
        "${systemctl}" --user restart quickshell.service || true
      fi
    '';
  }
