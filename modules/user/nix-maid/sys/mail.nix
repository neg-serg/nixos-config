{
  config,
  lib,
  pkgs,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  cfg = config.features.mail;
  passPkg = pkgs.pass.withExtensions (exts: [ exts.pass-otp ]); # Stores, retrieves, generates, and synchronizes passwords ...

  # Helper to generate mbsync config
  # ... (rest of mkMbsyncConfig remains unchanged)
  mkMbsyncConfig = acct: ''
    IMAPAccount ${acct.name}
    Host ${acct.imap.host}
    User ${acct.userName}
    PassCmd "${acct.passCmd}"
    AuthMechs LOGIN
    TLSType IMAPS
    CertificateFile /etc/ssl/certs/ca-bundle.crt

    IMAPStore ${acct.name}-remote
    Account ${acct.name}

    MaildirStore ${acct.name}-local
    Subfolders Verbatim
    Path ${config.users.users.neg.home}/.local/mail/${acct.name}/
    Inbox ${config.users.users.neg.home}/.local/mail/${acct.name}/INBOX/

    Channel ${acct.name}
    Far :${acct.name}-remote:
    Near :${acct.name}-local:
    Patterns "INBOX" "[Gmail]/Sent Mail" "[Gmail]/Drafts" "[Gmail]/All Mail" "[Gmail]/Trash" "[Gmail]/Spam"
    Sync Pull
    Create Near
    Expunge Near
    SyncState *
  '';

  # Account definition
  account = {
    name = "gmail";
    userName = "serg.zorg@gmail.com";
    realName = "Sergey Miroshnichenko";
    address = "serg.zorg@gmail.com";
    passCmd = "pass show gmail/mbsync-app";
    imap = {
      host = "imap.gmail.com";
      port = 993;
    };
    smtp = {
      host = "smtp.gmail.com";
      port = 587;
    };
  };
in
{
  config = lib.mkIf (cfg.enable or false) (
    lib.mkMerge [
      {
        # System packages
        environment.systemPackages = [
          pkgs.isync # Free IMAP and Maildir mailbox synchronizer
          pkgs.neomutt # Command-line mail reader based on Mutt
          pkgs.msmtp # An SMTP client
          pkgs.notmuch # Thread-based email indexer, searcher and tagger
          pkgs.goimapnotify # Execute scripts on IMAP IDLE (new mail)
          passPkg # The standard unix password manager
          (pkgs.writeShellScriptBin "sync-mail" ''
            #!/usr/bin/env bash
            set -euo pipefail
            exec systemctl --user start --no-block mbsync-gmail.service
          '') # Helper script to trigger mail synchronization
        ];

        # Services
        systemd.user.services."mbsync-gmail" = {
          description = "Sync mail via mbsync (gmail)";
          path = [
            passPkg # password manager for PassCmd
            # gnupg is installed via gpg.nix
          ];
          serviceConfig = {
            Type = "simple";
            TimeoutStartSec = "30min";
            ExecStart = "${lib.getExe pkgs.isync} -c %h/.config/mbsync/mbsyncrc -a"; # Free IMAP and MailDir mailbox synchronizer
          };
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
        };

        systemd.user.timers."mbsync-gmail" = {
          description = "Timer: mbsync gmail";
          timerConfig = {
            OnBootSec = "2m";
            OnUnitActiveSec = "10m";
            Persistent = true;
          };
          wantedBy = [ "timers.target" ];
        };

        systemd.user.services."imapnotify-gmail" = {
          description = "IMAP Notify (gmail)";
          path = [
            passPkg # password manager for passwordCmd
            # gnupg is installed via gpg.nix
          ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${lib.getExe pkgs.goimapnotify} -conf %h/.config/imapnotify/gmail.json"; # Execute scripts on IMAP mailbox changes (new/deleted/upda...
            Restart = "on-failure";
            RestartSec = "20";
          };
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "default.target" ]; # Using standard unwantedBy since we don't have the wrapper handy or want simple start
        };
      }

      (n.mkHomeFiles {
        # ========================================================================
        # MUTT / NEOMUTT
        # ========================================================================
        ".config/mutt" = {
          source = ../mutt-conf;
        };

        # ========================================================================
        # MBSYNC (ISYNC)
        # ========================================================================
        ".config/mbsync/mbsyncrc".text = mkMbsyncConfig account;

        # ========================================================================
        # MSMTP
        # ========================================================================
        ".config/msmtp/config".text = ''
          defaults
          auth           on
          tls            on
          tls_trust_file /etc/ssl/certs/ca-bundle.crt
          logfile        ~/.cache/msmtp.log

          account        ${account.name}
          host           ${account.smtp.host}
          port           ${toString account.smtp.port}
          from           ${account.address}
          user           ${account.userName}
          passwordeval   "${account.passCmd}"

          account default : ${account.name}
        '';

        # Environment Variables
        # Note: Notmuch default config location is ~/.notmuch-config, but we explicitly set it here
        # in case we want to move it later or purely for variable completeness.
        # However, the file generated below is at ~/.notmuch-config.
        # If we wanted to follow XDG, we'd put it in .config/notmuch/config and set this variable.
        # For now, matching the legacy/standard notmuch path.
        # BUT, envs.nix had: NOTMUCH_CONFIG = "${configHome}/notmuch/notmuchrc";
        # Let's honor the refactoring plan but notice the discrepancy.
        # The mkHomeFiles below currently writes to ".notmuch-config" (home root).
        # To clean this up, let's move the file to XDG and set the variable.
      })

      {
        environment.variables.NOTMUCH_CONFIG = "${config.users.users.neg.home}/.config/notmuch/notmuchrc";
      }

      (n.mkHomeFiles {
        # ... (existing files)
        # ========================================================================
        # NOTMUCH
        # ========================================================================
        ".config/notmuch/notmuchrc".text = ''
          [database]
          path=${config.users.users.neg.home}/.local/mail

          [user]
          name=${account.realName}
          primary_email=${account.address}

          [new]
          tags=unread;inbox;
          ignore=

          [search]
          exclude_tags=deleted;spam;

          [maildir]
          synchronize_flags=true
        '';

        # ========================================================================
        # IMAPNOTIFY
        # ========================================================================
        ".config/imapnotify/gmail.json".text = builtins.toJSON {
          host = account.imap.host;
          port = account.imap.port;
          tls = true;
          tlsOptions = {
            rejectUnauthorized = false;
          };
          username = account.userName;
          passwordCmd = account.passCmd;
          onNewMail = "${config.users.users.neg.home}/.config/mutt/scripts/sync_mail";
          boxes = [ "INBOX" ];
        };
      })
    ]
  );
}
