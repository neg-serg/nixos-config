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

  # --- Beets distrobox wrapper ---
  beetWrapper = pkgs.writeShellScriptBin "beet" ''
    set -euo pipefail
    CONTAINER="cachyos-beets"
    if ! distrobox list 2>/dev/null | grep -qw "$CONTAINER"; then
      distrobox create \
        --image "cachyos/cachyos:latest" \
        --name "$CONTAINER" \
        --yes
      distrobox enter "$CONTAINER" -- sudo pacman -S --noconfirm beets
    fi
    exec distrobox enter "$CONTAINER" -- beet "$@"
  '';

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
      spotify_path = "${pkgs.spotify}/share/spotify"; # Path to Spotify desktop files
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

in
lib.mkMerge [
  {
    environment.systemPackages =
      (lib.optionals (config.features.media.audio.beets.enable or true) (
        if config.features.media.audio.beets.mode == "distrobox"
        then [ beetWrapper ] # Music library manager and tagger (via distrobox/CachyOS)
        else [ pkgs.beets ] # Music library manager and tagger (native)
      ))
      ++ [
      # Audio
      pkgs.mpc # A minimalist command line interface to MPD
      pkgs.rmpc # Rust Music Player Client
      pkgs.rescrobbled # MPRIS Scrobbler # MPRIS Scrobbler
      pkgs.ncpamixer # An ncurses mixer for PulseAudio
      pkgs.playerctl # Command-line controller for MPC-capable players

      # Images
      pkgs.swayimg # Lightweight image viewer for Wayland
      pkgs.mpdas # Audio Scrobbler client for MPD
      pkgs.mpdris2 # MPRIS 2 support for MPD
    ]
    ++ lib.optionals (config.features.media.audio.spicetify.enable or false) [
      pkgs.spicetify-cli # Spotify customization tool
    ];

    # MPD Service
    # Note: MPD is enabled system-wide in modules/servers/mpd/default.nix
    # systemd.user.services.mpd is removed to avoid conflicts.

    # MPD RIS2 (MPRIS support)
    systemd.user.services.mpdris2 = {
      description = "MPD MPRIS2 Bridge";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe' pkgs.mpdris2 "mpDris2"}"; # Start MPD MPRIS2 bridge
        Restart = "on-failure";
      };
    };

    # Rescrobbled (MPRIS Scrobbler)
    systemd.user.services.rescrobbled = {
      description = "MPRIS music scrobbler daemon";
      after = [ "network-online.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.rescrobbled}"; # MPRIS Scrobbler
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

    ".config/rmpc".source = ../../../../files/rmpc;

    ".config/swayimg".source = ../../../../files/gui/swayimg;

    ".config/ncpamixer.conf".text = ''
      theme = "c0r73x"

      [theme-c0r73x]
      bar-start = "|"
      bar-normal = "."
      bar-end = "|"
      color-state = "blue"

      [settings]
      appearance = "auto"
      mouse-wheel-step = 1

      [keybindings]
      up = "k"
      down = "j"
      mute-toggle = "m"
      tab-next = "n"
      tab-prev = "p"
      volume-up = "+"
      volume-down = "-"
      volume-up-1 = "K"
      volume-down-1 = "J"
      volume-up-5 = "5"
      volume-down-5 = "6"
      volume-set-0 = "0"
      volume-set-10 = "1"
      volume-set-20 = "2"
      volume-set-30 = "3"
      volume-set-40 = "4"
      volume-set-50 = "5"
      volume-set-60 = "6"
      volume-set-70 = "7"
      volume-set-80 = "8"
      volume-set-90 = "9"
      volume-set-100 = "0"
      set-default = "d"
      tab-playback = "F1"
      tab-recording = "F2"
      tab-output = "F3"
      tab-input = "F4"
      tab-config = "F5"
    '';

    ".config/wiremix/wiremix.toml".text = ''
      # Wiremix Configuration
      theme = "nocolor"
      char_set = "compat"

      [names]
      stream = [ "{node:node.name}: {node:media.name}" ]

      keybindings = [
       { key = { F = 1 }, action = { SelectTab = 0 } },
       { key = { F = 2 }, action = { SelectTab = 1 } },
       { key = { F = 3 }, action = { SelectTab = 2 } },
       { key = { F = 4 }, action = { SelectTab = 3 } },
       { key = { F = 5 }, action = { SelectTab = 4 } },
      ]
    '';

    # Spicetify Config (partial management)
    ".config/spicetify/config-xpui.ini" =
      lib.mkIf (config.features.media.audio.spicetify.enable or false)
        {
          text = lib.generators.toINI { } spiceSettings;
        };

    # Rescrobbled Config
    ".config/rescrobbled/config.toml".text = ''
      [lastfm]
      api_key = "d374b5a27d6536dc09e105eefad6530c"
      secret = "ef5ec843f664b52332b61b5884b8d0dd"
      # session_key = "" # Generated via `rescrobbled` auth
    '';
  })
  (lib.mkIf (builtins.pathExists ../../../../secrets/home/mpdas/neg.rc) {
    sops.secrets."mpdas_negrc" = {
      sopsFile = ../../../../secrets/home/mpdas/neg.rc;
      format = "binary";
      owner = "neg";
    };
    # mpdas disabled because Last.fm password auth (error code 11) no longer works.
    # Use rescrobbled instead — run `rescrobbled auth` to generate a session_key.
    # systemd.user.services.mpdas = {
    #   description = "mpdas last.fm scrobbler";
    #   after = [ "sound.target" ];
    #   wantedBy = [ "default.target" ];
    #   serviceConfig = {
    #     ExecStart = "${lib.getExe pkgs.mpdas} -c ${config.sops.secrets.mpdas_negrc.path}"; # Start Last.fm scrobbler
    #     Restart = "on-failure";
    #   };
    # };
  })
  (lib.mkIf (config.features.media.aiUpscale.enable or false) (
    n.mkHomeFiles {
      ".local/bin/ai-upscale-video" = {
        executable = true;
        text = builtins.readFile ../scripts/ai-upscale-video.sh;
      };
      ".config/mpv/scripts/realesrgan.vpy".text = builtins.readFile ../scripts/realesrgan.vpy;
    }
  ))
]
