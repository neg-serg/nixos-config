{
  pkgs,
  lib,
  config,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  # --- Beets Config ---
  beetsSettings = {
    plugins = [
      "bpm"
      "chroma"
      "duplicates"
      "edit"
      "embedart"
      "export"
      "fetchart"
      "fromfilename"
      "ftintitle"
      "fuzzy"
      "hook"
      "info"
      "inline"
      "lastgenre"
      "lyrics"
      "mbsync"
      "missing"
      "mpdstats"
      "parentdir"
      "playlist"
      "scrub"
      "smartplaylist"
      "types"
    ];
    directory = "~/music/";
    library = "~/.config/beets/musiclibrary.db";
    import = {
      copy = false;
      move = true;
      write = true;
    };
  };

  # --- Spicetify Config ---
  spiceSettings = {
    Setting = {
      spotify_path = "${pkgs.spotify}/share/spotify";
      prefs_path = "${config.users.users.neg.home}/.config/spotify/prefs";
      current_theme = "Ziro";
      color_scheme = "rose-pine-moon";
      inject_css = true;
      replace_colors = true;
      overwrite_assets = true;
    };
  };

  # --- MPD Config ---
  mpdConfig = ''
    music_directory    "~/music"
    playlist_directory "~/.config/mpd/playlists"
    db_file            "~/.config/mpd/database"
    log_file           "syslog"
    pid_file           "~/.config/mpd/pid"
    state_file         "~/.config/mpd/state"
    sticker_file       "~/.config/mpd/sticker.sql"

    auto_update "yes"
    bind_to_address "any"

    audio_output {
      type "pipewire"
      name "PipeWire Output"
    }

    audio_output {
      type   "fifo"
      name   "my_fifo"
      path   "/tmp/mpd.fifo"
      format "44100:16:2"
    }
  '';

  # --- RMPC Source ---
  rmpcSrc = ../../../../files/rmpc;

  # --- Swayimg Source ---
  swayimgSrc = ../../../../files/gui/swayimg;

  # --- NCPAMixer Source ---
  ncpamixerConf = ../../../../files/gui/ncpamixer.conf;
in
lib.mkMerge [
  {
    environment.systemPackages = [
      # Audio
      pkgs.beets # Music library manager and tagger
      pkgs.mpc # A minimalist command line interface to MPD
      pkgs.rmpc # Rust Music Player Client
      pkgs.neg.lucida # Lucida.to downloader
      pkgs.neg.rescrobbled # MPRIS Scrobbler
      pkgs.ncpamixer # An ncurses mixer for PulseAudio
      pkgs.playerctl # Command-line controller for MPC-capable players

      # Images
      pkgs.swayimg # Lightweight image viewer for Wayland
      pkgs.mpdas # Audio Scrobbler client for MPD
      pkgs.mpdris2 # MPRIS 2 support for MPD
      pkgs.spicetify-cli # Spotify customization tool
    ];

    # Secrets for MPDAS
    sops.secrets."mpdas_negrc" = {
      sopsFile = ../../../../secrets/home/mpdas/neg.rc;
      format = "binary";
      owner = "neg";
    };

    environment.sessionVariables = {
      MPD_HOST = "localhost";
      MPD_PORT = "6600";
    };

    # MPD Service
    systemd.user.services.mpd = {
      enable = true;
      description = "Music Player Daemon";
      documentation = [
        "man:mpd(1)"
        "man:mpd.conf(5)"
      ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.mpd} --no-daemon";
        Restart = "on-failure";
      };
    };

    # MPD RIS2 (MPRIS support)
    systemd.user.services.mpdris2 = {
      description = "MPD MPRIS2 Bridge";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe' pkgs.mpdris2 "mpDris2"}";
        Restart = "on-failure";
      };
    };

    # MPDAS (Last.fm Scrobbler)
    systemd.user.services.mpdas = {
      description = "mpdas last.fm scrobbler";
      after = [ "sound.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.mpdas} -c ${config.sops.secrets.mpdas_negrc.path}";
        Restart = "on-failure";
      };
    };

    # Rescrobbled (MPRIS Scrobbler)
    systemd.user.services.rescrobbled = {
      description = "MPRIS music scrobbler daemon";
      after = [ "network-online.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.neg.rescrobbled}";
        Restart = "on-failure";
      };
    };
  }

  (n.mkHomeFiles {
    # Beets
    ".config/beets/config.yaml".text = builtins.toJSON beetsSettings;

    # MPD
    ".config/mpd/mpd.conf".text = mpdConfig;
    ".config/mpd/playlists/.keep".text = "";

    # MPD RIS2 Config
    ".config/mpDris2/mpDris2.conf".text = ''
      [Connection]
      host = localhost
      port = 6600
      music_dir = ${config.users.users.neg.home}/music
      [Bling]
      notify = False
      mmkeys = True
      can_quit = True
    '';

    # RMPC
    ".config/rmpc".source = n.linkImpure rmpcSrc;

    # Swayimg
    ".config/swayimg".source = n.linkImpure swayimgSrc;

    # NCPAMixer
    ".config/ncpamixer.conf".source = n.linkImpure ncpamixerConf;

    # Spicetify Config (partial management)
    ".config/spicetify/config-xpui.ini".text = lib.generators.toINI { } spiceSettings;

    # Rescrobbled Config
    ".config/rescrobbled/config.toml".text = ''
      [lastfm]
      api_key = "CHANGE_ME"
      secret = "CHANGE_ME"
      # session_key = "" # Generated via `rescrobbled` auth
    '';
  })

  (lib.mkIf (config.features.media.aiUpscale.enable or false) (
    n.mkHomeFiles {
      ".local/bin/ai-upscale-video" = {
        executable = true;
        text = builtins.readFile ../scripts/ai-upscale-video.sh;
      };
      ".config/mpv/scripts/realesrgan.vpy".source = n.linkImpure ../scripts/realesrgan.vpy;
    }
  ))
]
