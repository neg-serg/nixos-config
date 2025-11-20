{
  lib,
  pkgs,
  config,
  xdg,
  systemdUser,
  negLib,
  ...
}:
let
  mkLocalBin = negLib.mkLocalBin;
in
  with lib;
    mkIf config.features.mail.enable (lib.mkMerge [
    {
      # Install isync/mbsync and keep using the XDG config at ~/.config/isync/mbsyncrc
      programs.mbsync.enable = true;

      # Inline mbsyncrc under XDG with helper (guards parent and target)

      # Create base maildir on activation (mbsync can also create, but this avoids first-run hiccups)
      # Maildir creation handled by global prepareUserPaths action

      # Periodic sync in addition to imapnotify (fallback / catch-up)
      systemd.user.services."mbsync-gmail" = lib.mkMerge [
        {
          Unit.Description = "Sync mail via mbsync (gmail)";
          Service = {
            Type = "simple";
            TimeoutStartSec = "30min";
            ExecStart = let
              exe = lib.getExe pkgs.isync;
              args = ["-Va" "-c" "${config.xdg.configHome}/isync/mbsyncrc"];
            in "${exe} ${lib.escapeShellArgs args}";
          };
        }
        (systemdUser.mkUnitFromPresets {presets = ["netOnline"];})
      ];
      systemd.user.timers."mbsync-gmail" = lib.mkMerge [
        {
          Unit = {Description = "Timer: mbsync gmail";};
          Timer = {
            OnBootSec = "2m";
            OnUnitActiveSec = "10m";
            Persistent = true;
          };
        }
        (systemdUser.mkUnitFromPresets {presets = ["timers"];})
      ];
    }
    (mkLocalBin "sync-mail" ''
      #!/usr/bin/env bash
      set -euo pipefail
      exec systemctl --user start --no-block mbsync-gmail.service
    '')
    (xdg.mkXdgText "isync/mbsyncrc" (builtins.readFile ./mbsyncrc))
  ])
