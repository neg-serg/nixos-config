{
  pkgs,
  lib,
  config,
  impurity,
  ...
}: let
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
      "info"
      "lastgenre"
      "lastimport"
      "lyrics"
      "mbcollection"
      "mbsubmit"
      "mbsync"
      "mpdstats"
      "web"
    ];
    directory = "~/music";
    library = "~/music/library.db";
    threaded = "yes";
    color = "yes";
    ui = {color = "yes";};
    per_disc_numbering = "no";
    original_date = "yes";
    import = {
      copy = false;
      incremental_skip_later = true;
      quiet_fallback = true;
      none_rec_action = "skip";
      duplicate_action = "remove";
    };
    chroma = {auto = "yes";};
    lastgenre = {
      auto = true;
      canonical = true;
      count = 5;
    };
    match = {ignored = ["missing_tracks" "unmatched_tracks"];};
    fetchart = {
      auto = "yes";
      cover_names = ["front" "back"];
      sources = ["filesystem" "coverart" "itunes" "amazon" "albumart" "wikipedia" "google"];
    };
    embedart = {
      auto = "yes";
      remove_art_file = "no";
    };
    # lastfm = {user = "e7z0x1";};
    lyrics = {auto = "yes";};
    bbq = {fields = ["artist" "title" "album"];};
    include = [config.sops.secrets."musicbrainz.yaml".path];
  };

  # --- MPD/NCMPCPP Settings ---
  mpdHost = "localhost";
  mpdPort = 6600;
in {
  # --- System Packages ---
  environment.systemPackages = with pkgs; [
    # Audio
    beets # Music library manager and tagger
    mpd # Music Player Daemon
    mpdris2 # MPRIS2 bridge for MPD

    mpdas # Last.fm scrobbler for MPD
    rmpc # Rust Music Player Client
    ncpamixer # Ncurses mixer for PulseAudio/PipeWire
    # Subsonic
    subsonic-tui # TUI for Subsonic-compatible servers
    termsonic # Terminal client for Subsonic
    # Images
    swayimg # Image viewer for Wayland
    imv # Image viewer for Wayland and X11
    feh # Fast and light image viewer
    # Spotify
    spotify # Proprietary music streaming service
    spicetify-cli # Command-line tool to customize the Spotify client
  ];

  # --- Secrets (for Beets/MusicBrainz) ---
  sops.secrets."musicbrainz.yaml" = {
    sopsFile = ../../../secrets/home/musicbrainz;
    format = "binary";
    owner = "neg";
  };
  sops.secrets.mpdas_negrc = {
    sopsFile = ../../../secrets/home/mpdas/neg.rc;
    format = "binary";
    owner = "neg";
  };

  # --- Environment Variables ---
  environment.variables = {
    MPD_HOST = mpdHost;
    MPD_PORT = toString mpdPort;
  };

  users.users.neg.maid.file.home = {
    # --- Spicetify ---
    ".config/spicetify/config-xpui.ini".text = lib.generators.toINI {} {
      Setting = {
        spotify_path = "/nix/store"; # User will likely need to adjust this or use spicetify-nix
        prefs_path = "/home/neg/.config/spotify/prefs";
        current_theme = "catppuccin";
        color_scheme = "mocha";
        inject_css = 1;
        replace_colors = 1;
        overwrite_assets = 0;
        spotify_launch_flags = "";
        check_spicetify_upgrade = 0;
      };
      Preprocesses = {
        disable_sentry = 1;
        disable_ui_logging = 1;
        remove_rtl_rule = 1;
        expose_apis = 1;
      };
      AdditionalOptions = {
        extensions = "adblock.js|shuffle+.js|fullAppDisplay.js";
        custom_apps = "";
        sidebar_config = 1;
        home_config = 1;
        experimental_features = 1;
      };
    };

    # --- Beets ---
    ".config/beets/config.yaml".text = lib.generators.toYAML {} beetsSettings;

    # --- Swayimg ---
    # Wrapper script that redirects to swayimg-first (installed system-wide)
    ".local/bin/swayimg" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        exec swayimg-first "$@"
      '';
    };
    # Config symlink (lives in home/modules for live editing)
    ".config/swayimg".source = impurity.link "/etc/nixos/files/gui/swayimg";

    # --- RMPC ---
    # Config symlink (lives in home/modules for live editing)
    ".config/rmpc".source = impurity.link "/etc/nixos/files/rmpc";

    # --- NCPAMixer ---
    ".config/ncpamixer.conf".source = impurity.link "/etc/nixos/files/gui/ncpamixer.conf";

    # --- MPDris2 Config ---
    ".config/mpDris2/mpDris2.conf".text = lib.generators.toINI {} {
      Connection = {
        host = mpdHost;
        port = mpdPort;
        music_dir = "${config.users.users.neg.home}/music";
      };
      Bling = {
        notify = "false";
        mmkeys = "true";
      };
    };

    # --- AI Upscale Script ---
    ".local/bin/ai-upscale-video".text = builtins.readFile ./scripts/ai-upscale-video.sh;

    # --- AI Upscale VapourSynth (Real-time) ---
    ".config/mpv/vs/ai/realesrgan.vpy".text = builtins.readFile ./scripts/realesrgan.vpy;

    # --- MPD Config ---
    ".config/mpd/mpd.conf".text = ''
      music_directory "~/music"
      playlist_directory "~/.local/share/mpd/playlists"
      db_file "~/.local/share/mpd/database"
      log_file "syslog"
      state_file "~/.local/share/mpd/state"
      sticker_file "~/.local/share/mpd/sticker.sql"
      auto_update "yes"
      bind_to_address "${mpdHost}"
      port "${toString mpdPort}"
      restore_paused "yes"
      max_output_buffer_size "16384"

      audio_output {
        type "pipewire"
        name "PipeWire Sound Server"
      }

      audio_output {
        type "fifo"
        name "my_fifo"
        path "/tmp/audio.fifo"
        format "44100:16:2"
      }
    '';
  };

  # --- User Services (MPRIS, etc) ---
  systemd.user.services = {
    # MPD RIS2 (MPRIS support)
    mpdris2 = {
      description = "MPD MPRIS2 Bridge";
      after = ["mpd.service"];
      wantedBy = ["default.target"];
      serviceConfig = {
        ExecStart = "${pkgs.mpdris2}/bin/mpDris2";
        Restart = "on-failure";
        Environment = [
          "MPD_HOST=${mpdHost}"
          "MPD_PORT=${toString mpdPort}"
        ];
      };
    };

    # MPDAS (Last.fm Scrobbler)
    mpdas = {
      description = "mpdas last.fm scrobbler";
      after = ["sound.target" "sops-nix.service"];
      wantedBy = ["default.target"];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.mpdas} -c ${config.sops.secrets.mpdas_negrc.path}";
        Restart = "on-failure";
        RestartSec = "2";
      };
    };

    # Playerctld (MPRIS daemon)
    playerctld = {
      description = "Keep track of media player activity";
      wantedBy = ["default.target"];
      serviceConfig = {
        ExecStart = "${pkgs.playerctl}/bin/playerctld daemon";
        Restart = "on-failure";
      };
    };
  };
}
