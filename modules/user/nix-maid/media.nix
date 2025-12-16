{
  pkgs,
  lib,
  config,
  systemdUser,
  ...
}: let
  filesRoot = ../../../home/files;
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
  ];

  # --- Secrets (for Beets/MusicBrainz) ---
  sops.secrets."musicbrainz.yaml" = {
    sopsFile = config.neg.secretPath + "/home/musicbrainz";
    format = "binary";
    owner = "neg";
  };
  sops.secrets.mpdas_negrc = {
    sopsFile = config.neg.secretPath + "/home/mpdas_negrc";
    format = "binary";
    owner = "neg";
  };

  # --- Environment Variables ---
  environment.variables = {
    MPD_HOST = mpdHost;
    MPD_PORT = toString mpdPort;
  };

  users.users.neg.maid.file.home = {
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

    # --- RMPC Config ---
    ".config/rmpc".source = "${filesRoot}/rmpc/conf";

    # --- Swayimg Config ---
    ".config/swayimg".source = "${filesRoot}/swayimg/conf";

    # --- NCPAMixer ---
    ".config/ncpamixer.conf".source = "${filesRoot}/ncpamixer.conf";

    # --- AI Upscale Script ---
    ".local/bin/ai-upscale-video".text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      if [ $# -lt 1 ]; then
        echo "Usage: ai-upscale-video <input> [--anime] [--scale 4] [--crf 16]" >&2
        exit 1
      fi
      in="$1"; shift || true
      model="realesrgan-x4plus"
      scale=4
      crf=16
      while [ $# -gt 0 ]; do
        case "$1" in
          --anime) model="realesrgan-x4plus-anime"; shift ;;
          --scale)
            if [ $# -ge 2 ]; then scale="$2"; shift 2; else shift; fi ;;
          --crf)
            if [ $# -ge 2 ]; then crf="$2"; shift 2; else shift; fi ;;
          *) echo "Unknown arg: $1" >&2; exit 2 ;;
        esac
      done

      # Use global system packages; assume they are in PATH
      if ! command -v ffmpeg >/dev/null || ! command -v realesrgan-ncnn-vulkan >/dev/null; then
        echo "Missing dependencies: ffmpeg and realesrgan-ncnn-vulkan must be in PATH" >&2
        exit 3
      fi

      in_abs=$(readlink -f "$in")
      base_dir=$(dirname "$in_abs")
      base_name=$(basename "$in_abs")
      stem=$(printf '%s' "$base_name" | sed 's/\.[^.]*$//')
      out="$base_dir/$stem"_x"$scale"_realesrgan.mp4

      cache_root="$HOME/.cache/ai-upscale"
      mkdir -p "$cache_root"
      work=$(mktemp -d "$cache_root/work.XXXXXX")
      trap 'rm -rf "$work"' EXIT
      frames="$work/frames"; up="$work/up"
      mkdir -p "$frames" "$up"

      # Probe FPS
      fps=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$in_abs" | awk -F/ '{ if ($2==""||$2==0) print $1; else printf("%.6f\n", $1/$2) }')
      [ -z "$fps" ] && fps=30

      echo "[ai-upscale] Extracting frames…" >&2
      ffmpeg -hide_banner -loglevel error -y -i "$in_abs" -map 0:v:0 -vsync 0 -pix_fmt rgb24 "$frames/%08d.png"

      echo "[ai-upscale] Upscaling with $model (x$scale)…" >&2
      realesrgan-ncnn-vulkan -i "$frames" -o "$up" -n "$model" -s "$scale" -f png >/dev/null

      echo "[ai-upscale] Encoding output…" >&2
      ffmpeg -hide_banner -loglevel error -y -framerate "$fps" -i "$up/%08d.png" -i "$in_abs" \
        -map 0:v:0 -map 1:a? -map 1:s? -c:v libx264 -preset medium -crf "$crf" -pix_fmt yuv420p \
        -c:a copy -c:s copy "$out"

      echo "[ai-upscale] Done: $out" >&2
    '';

    # --- AI Upscale VapourSynth (Real-time) ---
    ".config/mpv/vs/ai/realesrgan.vpy".text = ''
      import vapoursynth as vs
      core = vs.core
      clip = video_in

      scale = 2
      want_anime = False

      def safe_int(x, default=2):
          try:
              v = int(x)
              return v if v in (2, 4) else default
          except Exception:
              return default

      try:
          import vsrealesrgan as vr
          model = 'realesr-animevideov3' if want_anime else 'realesrgan-x4plus'
          try:
              clip = vr.Realesrgan(clip, model=model, scale=scale)
          except Exception:
              try:
                  clip = core.realesrgan.Model(clip, model=model, scale=scale)
              except Exception:
                  pass
      except Exception:
          try:
              import vsmlrt
              clip = vsmlrt.Realesrgan(clip, scale=scale, anime=want_anime)
          except Exception:
              pass

      # Fallback
      try:
          if clip.width == video_in.width: # if no upscale happened
             clip = core.resize.Spline36(clip, width=clip.width * scale, height=clip.height * scale)
      except Exception:
          pass

      clip.set_output()
    '';
  };

  # --- User Services (MPD, etc) ---
  systemd.user.services = {
    # MPD RIS2 (MPRIS support)
    mpdris2 = {
      description = "MPD MPRIS2 Bridge";
      wantedBy = ["default.target"];
      serviceConfig = {
        ExecStart = "${pkgs.mpdris2}/bin/mpdris2";
        Restart = "on-failure";
      };
    };

    # MPDAS (Last.fm Scrobbler)
    mpdas = systemdUser.mkUnitFromPresets {
      presets = ["sops" "defaultWanted"];
      after = ["sound.target"];
      service = {
        ExecStart = "${lib.getExe pkgs.mpdas} -c ${config.sops.secrets.mpdas_negrc.path}";
        Restart = "on-failure";
      };
    };
  };
}
