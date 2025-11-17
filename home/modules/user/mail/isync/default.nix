{
  lib,
  pkgs,
  config,
  xdg,
  systemdUser,
  ...
}:
with lib;
  mkIf config.features.mail.enable (lib.mkMerge [
    {
      # Install isync/mbsync and keep using the XDG config at ~/.config/isync/mbsyncrc
      programs.mbsync.enable = true;

      # Inline mbsyncrc under XDG with helper (guards parent and target)

      # Optional: ensure the binary is present even if HM changes defaults
      # Also provide a non-blocking trigger to start sync in background
      home.packages = config.lib.neg.pkgsList [
        pkgs.isync # mbsync binary (isync)
        (pkgs.writeShellScriptBin "sync-mail" ''          # quick trigger to start mbsync unit
                 #!/usr/bin/env bash
                 set -euo pipefail
                 # Fire-and-forget start of the mbsync systemd unit
                 exec systemctl --user start --no-block mbsync-gmail.service
        '')
      ];

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
    (xdg.mkXdgText "isync/mbsyncrc" (builtins.readFile ./mbsyncrc))
  ])
