{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  inherit (config.users.users.neg) home;

  # --- rmpc: Russian-layout duplicate binds (ЙЦУКЕН) --------------------------
  # GENERATED from lib/ru-keys.nix (neg.ruKeys) — single source of truth, do not
  # edit the generated chars. Bind data lives below (rmpcRuBinds), the latin
  # binds live in files/rmpc/config.ron (markers rmpcRuBinds.*). The daemon
  # ru-layout (features.input.ruHotkeys) already forces us in the terminal, so
  # these duplicates only matter after a manual M4+S switch inside the window.
  ruKeys = neg.ruKeys;

  rmpcRuBinds = {
    global = [
      {
        key = "p";
        action = "TogglePause";
      }
      {
        key = "q";
        action = "Quit";
      }
      {
        key = "s";
        action = "Stop";
      }
      {
        key = "u";
        action = "Update";
      }
      {
        key = "w";
        action = "ShowHelp";
      }
      {
        key = "b";
        action = "SeekBack";
      }
      {
        key = "f";
        action = "SeekForward";
      }
      {
        key = "o";
        action = "ShowOutputs";
      }
      {
        key = "z";
        action = "ToggleRepeat";
      }
      {
        key = "r";
        action = "ToggleRandom";
      }
      {
        key = "y";
        action = "ToggleSingle";
      }
      {
        key = "L";
        action = "ExternalCommand(command: [\"mpc\", \"clear\"])";
      }
      {
        key = "O";
        action = "ShowOutputs";
      }
      {
        key = "P";
        action = "PlaylistsTab";
      }
      {
        key = "U";
        action = "Rescan";
      }
      {
        key = "R";
        action = "ToggleConsume";
      }
    ];
    navigation = [
      {
        key = "a";
        action = "Select";
      }
      {
        key = "A";
        action = "AddAll";
      }
      {
        key = "D";
        action = "Delete";
      }
      {
        key = "g";
        action = "Top";
      }
      {
        key = "G";
        action = "Bottom";
      }
      {
        key = "h";
        action = "Left";
      }
      {
        key = "i";
        action = "FocusInput";
      }
      {
        key = "j";
        action = "Down";
      }
      {
        key = "J";
        action = "MoveDown";
      }
      {
        key = "k";
        action = "Up";
      }
      {
        key = "K";
        action = "MoveUp";
      }
      {
        key = "l";
        action = "Right";
      }
      {
        key = "n";
        action = "NextResult";
      }
      {
        key = "N";
        action = "PreviousResult";
      }
      {
        key = "r";
        action = "Rename";
      }
    ];
    queue = [
      {
        key = "a";
        action = "AddToPlaylist";
      }
      {
        key = "C";
        action = "DeleteAll";
      }
      {
        key = "d";
        action = "Delete";
      }
    ];
  };

  # Generated lines keep the 12-space indent of the surrounding RON entries.
  rmpcRuLine = d: "            \"${ruKeys.toRu d.key}\": ${d.action}, // ${d.key}";

  # The markers in files/rmpc/config.ron carry the section header; the
  # generated block is just the bind lines (no trailing newline — the marker's
  # own line break follows).
  rmpcRuBlock = binds: lib.concatStringsSep "\n" (map rmpcRuLine binds);

  # files/rmpc/config.ron carries marker comments (rmpcRuBinds.*) where the
  # generated blocks are spliced in.
  rmpcConfig = builtins.readFile (config.lib.neg.path "files/rmpc/config.ron");
  rmpcText = lib.pipe rmpcConfig [
    (
      s:
      builtins.replaceStrings
        [
          "            // Russian layout duplicates (ЙЦУКЕН) — GENERATED (rmpcRuBinds.global), see modules/user/nix-maid/sys/media.nix"
        ]
        [ (rmpcRuBlock rmpcRuBinds.global) ]
        s
    )
    (
      s:
      builtins.replaceStrings
        [
          "            // Russian layout duplicates (ЙЦУКЕН) — GENERATED (rmpcRuBinds.navigation), see modules/user/nix-maid/sys/media.nix"
        ]
        [ (rmpcRuBlock rmpcRuBinds.navigation) ]
        s
    )
    (
      s:
      builtins.replaceStrings
        [
          "            // Russian layout duplicates (ЙЦУКЕН) — GENERATED (rmpcRuBinds.queue), see modules/user/nix-maid/sys/media.nix"
        ]
        [ (rmpcRuBlock rmpcRuBinds.queue) ]
        s
    )
  ];

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
      prefs_path = "${home}/.config/spotify/prefs";
      current_theme = "Ziro";
      color_scheme = "rose-pine-moon";
      inject_css = true;
      replace_colors = true;
      overwrite_assets = true;
    };
  };

in
lib.mkMerge [
  {
    environment.systemPackages =
      (lib.optionals (config.features.media.audio.beets.enable or true) (
        if config.features.media.audio.beets.mode == "distrobox" then
          [ beetWrapper ] # Music library manager and tagger (via distrobox/CachyOS)
        else
          [ pkgs.beets ] # Music library manager and tagger (native)
      ))
      ++ [ pkgs.sacad ] # Standalone cover art downloader for music library
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
      ++ lib.optionals (config.lib.neg.enabled "media.audio.spicetify") [
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

  (neg.mkHomeFiles {
    # Beets
    ".config/beets/config.yaml".text = builtins.toJSON beetsSettings;

    ".config/mpd/playlists/.keep".text = "";

    # MPD RIS2 Config
    ".config/mpDris2/mpDris2.conf".text = ''
      [Connection]
      host = localhost
      port = 6600
      music_dir = ${home}/music
      [Bling]
      notify = False
      mmkeys = True
      can_quit = True
    '';

    # rmpc config: config.ron is GENERATED (RU duplicates spliced at the
    # rmpcRuBinds.* markers), themes deployed as-is.
    ".config/rmpc/config.ron".text = rmpcText;
    ".config/rmpc/themes".source = config.lib.neg.path "files/rmpc/themes";

    ".config/swayimg".source = config.lib.neg.path "files/gui/swayimg";

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

    # Spicetify Config (partial management)
    ".config/spicetify/config-xpui.ini" = lib.mkIf (config.lib.neg.enabled "media.audio.spicetify") {
      text = lib.generators.toINI { } spiceSettings;
    };

    # Rescrobbled Config (from SOPS)
    ".config/rescrobbled/config.toml".source = config.sops.secrets."lastfm/rescrobbled".path;

    # GitHub .netrc for nix/git fetchers (authenticates to private repos,
    # avoids GitHub API rate limits on `nix flake lock --update-input`).
    ".netrc".source = config.sops.secrets."github-netrc".path;

  })
  {
    sops.secrets."lastfm/rescrobbled" = {
      sopsFile = config.lib.neg.path "secrets/home/lastfm-rescrobbled.sops";
      format = "binary";
      owner = "neg";
    };
    sops.secrets."github-netrc" = {
      sopsFile = config.lib.neg.path "secrets/github-netrc.sops.yaml";
      format = "yaml";
      key = "github-netrc";
      owner = "neg";
    };
    # Rescrobbled config sourced from SOPS above.
  }
  (lib.mkIf (config.lib.neg.pathExists "secrets/home/mpdas/neg.rc") {
    sops.secrets."mpdas_negrc" = {
      sopsFile = config.lib.neg.path "secrets/home/mpdas/neg.rc";
      format = "binary";
      owner = "neg";
    };
    # mpdas service lives in sys/user-services.nix.
  })
  (lib.mkIf (config.lib.neg.enabled "media.aiUpscale") (
    neg.mkHomeFiles {
      ".local/bin/ai-upscale-video" = {
        executable = true;
        text = builtins.readFile ../scripts/ai-upscale-video.sh;
      };
      ".config/mpv/scripts/realesrgan.vpy".text = builtins.readFile ../scripts/realesrgan.vpy;
    }
  ))
]
