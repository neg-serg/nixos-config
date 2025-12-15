{
  config,
  lib,
  pkgs,
  ...
}: let
  mediaEnabled = config.features.media.audio.mpd.enable or false;
  cfg =
    config.media.audio.mpd or {
      host = "localhost";
      port = 6600;
    }; # Fallback defaults if options missing
in
  lib.mkIf mediaEnabled {
    # Ensure system can decrypt user secrets using user's key
    sops.age.keyFile = "${config.users.users.neg.home}/.config/sops/age/keys.txt";

    # 1. Secrets (System-level sops)
    # Replaces HM definition in secrets/home/default.nix
    # 1. Secrets (System-level sops)
    # Replaces HM definition in secrets/home/default.nix
    sops.secrets."mpdas_negrc" = {
      sopsFile = ../../../secrets/home/mpdas/neg.rc;
      format = "binary";
      owner = "neg";
      # Default is /run/secrets/mpdas_negrc
    };

    # 2. Config Files (Nix-Maid)
    users.users.neg.maid.file.home = {
      # mpdris2 config
      ".config/mpdris2/mpdris2.conf".text = ''
        [Connection]
        host = ${cfg.host}
        port = ${toString cfg.port}
        music_dir = ${config.users.users.neg.home}/music
        [Bling]
        notify = False
        mmkeys = True
        can_quit = True
      '';

      # Environment variables for session
      # We can set session variables via environment.extraInit or environment.sessionVariables
    };

    environment.sessionVariables = {
      MPD_HOST = cfg.host;
      MPD_PORT = toString cfg.port;
    };

    # 3. Systemd User Services
    systemd.user.services = {
      # mpdas: Audio Scrobbler
      mpdas = {
        description = "mpdas last.fm scrobbler";
        after = ["sound.target"];
        wantedBy = ["default.target"]; # Autostart
        serviceConfig = {
          # Use the system-level sops secret path
          ExecStart = "${lib.getExe pkgs.mpdas} -c ${config.sops.secrets."mpdas_negrc".path}";
          Restart = "on-failure";
          RestartSec = "2";
        };
      };

      # mpdris2: MPRIS2 support for MPD
      mpdris2 = {
        description = "MPRIS2 support for MPD";
        after = ["mpd.service"]; # Assuming mpd runs or is remote
        wantedBy = ["default.target"];
        serviceConfig = {
          ExecStart = "${lib.getExe pkgs.mpdris2}";
          Restart = "on-failure";
        };
      };
    };

    # Ensure packages
    environment.systemPackages = [
      pkgs.mpdas
      pkgs.mpdris2
    ];
  }
