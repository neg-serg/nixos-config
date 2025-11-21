{
  lib,
  pkgs,
  config,
  systemdUser,
  negLib,
  ...
}:
let
  inherit (lib) mkIf;
  mkLocalBin = negLib.mkLocalBin;
  # The custom helper from this flake. We need to import it to use it.
  xdg = import ../../../lib/xdg-helpers.nix { inherit pkgs; };

  # Dynamically generate the mbsyncrc content from the accounts configuration
  mbsyncrcContent = lib.concatStringsSep "\n\n" (lib.mapAttrsToList (name: account: ''
    #-- ${name}
    IMAPAccount ${name}
    Host ${account.imap.host}
    User ${account.userName}
    PassCmd "${lib.head account.passwordCommand}"
    AuthMechs LOGIN
    SSLType IMAPS
    CertificateFile /etc/ssl/certs/ca-bundle.crt

    IMAPStore ${name}-remote
    Account ${name}

    MaildirStore ${name}-local
    Subfolders Verbatim
    Path ${config.xdg.dataHome}/mail/${name}/
    Inbox ${config.xdg.dataHome}/mail/${name}/INBOX/

    Channel ${name}
    Far :${name}-remote:
    Near :${name}-local:
    Patterns "INBOX" "[Gmail]/Sent Mail" "[Gmail]/Drafts" "[Gmail]/All Mail" "[Gmail]/Trash" "[Gmail]/Spam"
    Sync Pull
    Create Near
    Expunge Near
    SyncState *
  '') config.accounts.email.accounts);
in
  # This is a list of attribute sets that will be merged.
  # We are NOT using the programs.mbsync module anymore to avoid conflicts.
  mkIf config.features.mail.enable (lib.mkMerge [
    {
      # 1. Install the package directly
      home.packages = [ pkgs.isync ];
    }

    # 2. Manually create the config file using the flake's own helper function.
    # This was the original (and correct) way of creating the file.
    (xdg.mkXdgText "mbsync/mbsyncrc" mbsyncrcContent)

    {
      # 3. Define the periodic sync timer/service
      systemd.user.services."mbsync-gmail" = lib.mkMerge [
        {
          Unit.Description = "Sync mail via mbsync (gmail)";
          Service = {
            Type = "simple";
            TimeoutStartSec = "30min";
            # We must explicitly specify the config file path now that we are not using the HM module.
            ExecStart = "${lib.getExe pkgs.isync} -c ${config.xdg.configHome}/mbsync/mbsyncrc -a";
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

    # 4. Local bin helper to trigger a sync manually
    (mkLocalBin "sync-mail" ''
      #!/usr/bin/env bash
      set -euo pipefail
      exec systemctl --user start --no-block mbsync-gmail.service
    '')
  ])
