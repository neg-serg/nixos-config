{
  config,
  lib,
  pkgs,
  neg,
  ...
}:
let
  inherit (config.users.users.neg) home;
  cfg = config.features.mail;
  passPkg = pkgs.pass.withExtensions (exts: [ exts.pass-otp ]); # Stores, retrieves, generates, and synchronizes passwords ...

  # Helper to generate mbsync config
  # ... (rest of mkMbsyncConfig remains unchanged)
  mkMbsyncConfig =
    acct:
    builtins.replaceStrings
      [
        "@NAME@"
        "@HOST@"
        "@USERNAME@"
        "@PASSCMD@"
        "@NAME_V2@"
        "@NAME_V3@"
        "@NAME_V4@"
        "@HOME@"
        "@NAME_V5@"
        "@HOME_V2@"
        "@NAME_V6@"
        "@NAME_V7@"
        "@NAME_V8@"
        "@NAME_V9@"
      ]
      [
        "${acct.name}"
        "${acct.imap.host}"
        "${acct.userName}"
        "${acct.passCmd}"
        "${acct.name}"
        "${acct.name}"
        "${acct.name}"
        "${home}"
        "${acct.name}"
        "${home}"
        "${acct.name}"
        "${acct.name}"
        "${acct.name}"
        "${acct.name}"
      ]
      (builtins.readFile (config.lib.neg.path "files/config/mbsync/mbsyncrc"));

  # Account definition
  account = {
    name = "gmail";
    userName = "serg.zorg@gmail.com";
    realName = "Sergey Miroshnichenko";
    address = "serg.zorg@gmail.com";
    passCmd = "pass show mail/gmail/serg.zorg@gmail.com/mbsync-app";
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

        systemd.user.services."mbsync-gmail" = lib.mkIf cfg.mbsync.enable {
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

        systemd.user.timers."mbsync-gmail" = lib.mkIf cfg.mbsync.enable {
          description = "Timer: mbsync gmail";
          timerConfig = {
            OnBootSec = "2m";
            OnUnitActiveSec = "10m";
            Persistent = true;
          };
          wantedBy = [ "timers.target" ];
        };
      }

      (neg.mkHomeFiles {
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
        environment.variables.NOTMUCH_CONFIG = "${home}/.config/notmuch/notmuchrc";
      }

      (neg.mkHomeFiles {
        # ... (existing files)
        # ========================================================================
        # NOTMUCH
        # ========================================================================
        ".config/notmuch/notmuchrc".text = ''
          [database]
          path=${home}/.local/mail

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
          onNewMail = "${home}/.config/mutt/scripts/sync_mail";
          boxes = [ "INBOX" ];
        };
      })
    ]
  );
}
