##
# Module: user/nix-maid/sys/user-services/trash-cleanup
# Purpose: keep the freedesktop Trash from growing forever. Files land there
# from `gio trash`, file managers and cleanup scripts; nothing ever removes
# them, so odin carried 4.3G of debris (oldest entry: April). Entries older
# than 30 days are dropped daily; the rest is left alone so a recent "oops"
# is still recoverable.
# Key options: features.trashCleanup.enable (default true).
# Dependencies: pkgs (coreutils/findutils in the wrapper's PATH).
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkIf
    getExe
    ;
  cfg = config.features.trashCleanup;

  # Freedesktop Trash layout: files/<name> plus info/<name>.trashinfo are
  # created together, so both sides use the same age filter and go together.
  cleanupScript = pkgs.writeShellApplication {
    name = "trash-cleanup";
    runtimeInputs = [
      pkgs.coreutils # rm/read for the deletion loop
      pkgs.findutils # find with the -mtime age filter
    ];
    text = ''
      set -euo pipefail

      trash="''${XDG_DATA_HOME:-$HOME/.local/share}/Trash"
      days=30
      [ -d "$trash/files" ] || exit 0

      find "$trash/files" -mindepth 1 -maxdepth 1 -mtime "+$days" -print0 |
        while IFS= read -r -d "" item; do
          rm -rf -- "$item"
        done
      find "$trash/info" -mindepth 1 -maxdepth 1 -name "*.trashinfo" -mtime "+$days" -delete
    '';
  };
in
mkIf cfg.enable {
  systemd.user.services.trash-cleanup = {
    description = "Empty Trash entries older than 30 days";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = getExe cleanupScript;
    };
  };

  systemd.user.timers.trash-cleanup = {
    description = "Timer: empty old Trash entries daily";
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "30m";
      Persistent = true;
      Unit = "trash-cleanup.service";
    };
    wantedBy = [ "timers.target" ];
  };
}
