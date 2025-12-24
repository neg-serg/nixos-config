{
  config,
  lib,
  pkgs,
  neg,
  impurity ? null,
  ...
}: let
  n = neg impurity;
  cfg = config.features.mail;

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
in {
  config = lib.mkIf (cfg.enable or false) (lib.mkMerge [
    {
      # System packages
      environment.systemPackages = [
        pkgs.isync # Free IMAP and Maildir mailbox synchronizer
        pkgs.neomutt # Command-line mail reader based on Mutt
        pkgs.msmtp # An SMTP client
        pkgs.notmuch # Thread-based email indexer, searcher and tagger
        pkgs.goimapnotify # Execute scripts on IMAP IDLE (new mail)
        pkgs.pass # The standard unix password manager
        (pkgs.writeShellScriptBin "sync-mail" ''
          #!/usr/bin/env bash
          set -euo pipefail
          exec systemctl --user start --no-block mbsync-gmail.service
        '') # Helper script to trigger mail synchronization
      ];

      # Services
      systemd.user.services."mbsync-gmail" = {
        description = "Sync mail via mbsync (gmail)";
        serviceConfig = {
          Type = "simple";
          TimeoutStartSec = "30min";
          ExecStart = "${lib.getExe pkgs.isync} -c %h/.config/mbsync/mbsyncrc -a";
        };
        after = ["network-online.target"];
        wants = ["network-online.target"];
      };

      systemd.user.timers."mbsync-gmail" = {
        description = "Timer: mbsync gmail";
        timerConfig = {
          OnBootSec = "2m";
          OnUnitActiveSec = "10m";
          Persistent = true;
        };
        wantedBy = ["timers.target"];
      };

      systemd.user.services."imapnotify-gmail" = {
        description = "IMAP Notify (gmail)";
        serviceConfig = {
          Type = "simple";
          ExecStart = "${lib.getExe pkgs.goimapnotify} -conf %h/.config/imapnotify/gmail.conf";
          Restart = "on-failure";
          RestartSec = "20";
        };
        after = ["network-online.target"];
        wants = ["network-online.target"];
        wantedBy = ["default.target"]; # Using standard unwantedBy since we don't have the wrapper handy or want simple start
      };
    }

    (n.mkHomeFiles {
      # ========================================================================
      # MUTT / NEOMUTT
      # ========================================================================
      ".config/mutt" = {
        source = ./mutt-conf;
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

      # ========================================================================
      # NOTMUCH
      # ========================================================================
      ".notmuch-config".text = ''
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
      ".config/imapnotify/gmail.conf".text = builtins.toJSON {
        host = account.imap.host;
        port = account.imap.port;
        tls = true;
        tlsOptions = {rejectUnauthorized = false;};
        username = account.userName;
        passwordCmd = account.passCmd;
        onNewMail = "${config.users.users.neg.home}/.config/mutt/scripts/sync_mail";
        boxes = ["INBOX"];
      };
    })
  ]);
}
