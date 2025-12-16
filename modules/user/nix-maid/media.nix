{
  pkgs,
  lib,
  config,
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

  ncmpcppSettings = {
    mpd_host = mpdHost;
    mpd_port = mpdPort;
    mpd_crossfade_time = "0";
    ncmpcpp_directory = "${config.users.users.neg.home}/.config/ncmpcpp";
    autocenter_mode = "yes";
    centered_cursor = "yes";
    user_interface = "classic";
    locked_screen_width_part = "70";
    display_bitrate = "yes";
    mouse_support = "no";
    use_console_editor = "yes";
    external_editor = "nvim";
    jump_to_now_playing_song_at_start = "yes";
    ask_before_clearing_playlists = "no";
    song_window_title_format = "ncmpcpp";
    default_find_mode = "wrapped";
    playlist_disable_highlight_delay = "1";
    playlist_show_remaining_time = "yes";
    playlist_shorten_total_times = "yes";
    playlist_display_mode = "classic";
    progressbar_look = "─╼ ";
    progressbar_color = "black";
    progressbar_elapsed_color = "239";
    song_status_format = "{$8%a} $(26)❯$(26)> {$8%t} $(26)❯$(26)> $b{$8%b}$/b $b({$8%y})$/b$(end)";
    song_list_format = "$(57)%5n  $(7)%26a$7$(238) ❯ $(250)%44t$(1)$R$(238)❮ $(250)%5l $7%28b$(end)";
    song_library_format = "{$(3)%n$(end)$(26) ❯ $(end)}{%t}|{%f}";
    current_item_prefix = "$b$(26)❯>";
    current_item_suffix = "$/b$/r$(end)";
    header_visibility = "no";
    statusbar_visibility = "no";
    media_library_primary_tag = "artist";
    media_library_albums_split_by_date = "yes";
    colors_enabled = "yes";
    main_window_color = "default";
    visualizer_data_source = "/tmp/audio.fifo";
    visualizer_output_name = "my_fifo";
    visualizer_type = "ellipse";
    visualizer_look = "▞▋";
  };
in {
  # --- System Packages ---
  environment.systemPackages = with pkgs; [
    # Audio
    beets
    mpd
    mpdris2
    ncmpcpp
    mpdas
    rmpc
    ncpamixer
    # Subsonic
    subsonic-tui
    termsonic
    # Images
    swayimg
    imv
    feh
    # Spotify
    spotify
    spicetify-cli
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

    # --- NCMPCPP ---
    # Generate config and bindings
    ".config/ncmpcpp/config".text = lib.generators.toKeyValue {} ncmpcppSettings;
    # Bindings are complex list of sets in standard HM, but ncmpcpp bindings file is just "def_key <key> <command>"
    # We will skip manual bindings generation for now and rely on defaults or if user has a custom bindings file, it should be in home/files.
    # User's previous ncmpcpp.nix had a list, we can generate it:
    ".config/ncmpcpp/bindings".text = ''
      def_key "0" "show_browser"
      def_key "1" "show_playlist"
      def_key "2" "show_media_library"
      def_key "a" "add_selected_items"
      def_key "backspace" "jump_to_parent_directory"
      def_key "backspace" "replay_song"
      def_key "b" "seek_backward"
      def_key "c" "clear_main_playlist"
      def_key "`" "add_random_items"
      def_key "/" "find_item_forward"
      def_key "~" "jump_to_media_library"
      def_key ";" "jump_to_position_in_song"
      def_key ">" "next"
      def_key "<" "previous"
      def_key "]" "scroll_down_album"
      def_key "}" "scroll_down_artist"
      def_key "[" "scroll_up_album"
      def_key "{" "scroll_up_artist"
      def_key "?" "show_search_engine"
      def_key "@" "show_server_info"
      def_key "|" "toggle_mouse"
      def_key "-" "volume_down"
      def_key "+" "volume_up"
      def_key "ctrl-d" "page_down"
      def_key "ctrl-l" "toggle_screen_lock"
      def_key "ctrl-u" "page_up"
      def_key "d" "delete_playlist_items"
      def_key "e" "edit_song"
      def_key "f" "seek_forward"
      def_key "g" "move_home"
      def_key "G" "move_end"
      def_key "h" "previous_column"
      def_key "l" "next_column"
      def_key "i" "show_song_info"
      def_key "j" "scroll_down"
      def_key "k" "scroll_up"
      def_key "L" "dummy"
      def_key "m" "show_media_library"
      def_key "n" "next_found_item"
      def_key "N" "previous_found_item"
      def_key "p" "pause"
      def_key "q" "quit"
      def_key "r" "jump_to_playing_song"
      def_key "s" "stop"
      def_key "y" "save_tag_changes"
    '';

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
    ".config/swayimg".source = ../../../files/gui/swayimg;

    # --- RMPC ---
    # Config symlink (lives in home/modules for live editing)
    ".config/rmpc".source = ../../../files/rmpc;

    # --- NCPAMixer ---
    ".config/ncpamixer.conf".source = ../../../files/gui/ncpamixer.conf;

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

  # --- User Services (MPD, etc) ---
  systemd.user.services = {
    # MPD Service
    mpd = {
      description = "Music Player Daemon";
      after = ["network.target" "sound.target"];
      wantedBy = ["default.target"];
      serviceConfig = {
        ExecStart = "${pkgs.mpd}/bin/mpd --no-daemon";
        Type = "notify";
      };
    };

    # MPD RIS2 (MPRIS support)
    mpdris2 = {
      description = "MPD MPRIS2 Bridge";
      wantedBy = ["default.target"];
      serviceConfig = {
        ExecStart = "${pkgs.mpdris2}/bin/mpdris2";
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
