{
  pkgs,
  lib,
  config,
  neg,
  impurity ? null,
  ...
}: let
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
        pkgs.neg.rmpc # Rust Music Player Client
        pkgs.ncpamixer # An ncurses mixer for PulseAudio
        pkgs.pavucontrol # PulseAudio Volume Control
        pkgs.pwvucontrol # PipeWire volume control (GTK)
        pkgs.playerctl # Command-line controller for MPC-capable players

        # Images
        pkgs.swayimg # Lightweight image viewer for Wayland

        # Video
        pkgs.mpv # Open source media player
      ];

      # MPD Service
      systemd.user.services.mpd = {
        enable = true;
        description = "Music Player Daemon";
        documentation = ["man:mpd(1)" "man:mpd.conf(5)"];
        partOf = ["graphical-session.target"];
        wantedBy = ["graphical-session.target"];
        serviceConfig = {
          ExecStart = "${pkgs.mpd}/bin/mpd --no-daemon";
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

      # RMPC
      ".config/rmpc".source = n.linkImpure rmpcSrc;

      # Swayimg
      ".config/swayimg".source = n.linkImpure swayimgSrc;

      # NCPAMixer
      ".config/ncpamixer.conf".source = n.linkImpure ncpamixerConf;

      # Spicetify Config (partial management)
      ".config/spicetify/config-xpui.ini".text = lib.generators.toINI {} spiceSettings;
    })
  ]
