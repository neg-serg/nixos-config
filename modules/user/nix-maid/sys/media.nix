{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  inherit (config.users.users.neg) home;

  # Module-shaped systemd user units (lib/systemd-user.nix)
  systemdUser = config.lib.neg.systemdUser;

  # sacad downloads album art on demand only, so it is built on first use.
  onDemand = config.lib.neg.onDemand pkgs;

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
      ++ [
        (onDemand {
          name = "sacad";
          attr = "sacad";
        }) # cover art downloader for the music library, built on first use
      ]
      ++ [
        # Audio
        pkgs.mpc # A minimalist command line interface to MPD
        pkgs.euphonica # GTK4/libadwaita MPD client (GUI MPD frontend)
        pkgs.playerctl # Command-line controller for MPC-capable players

        # Images
        pkgs.swayimg # Lightweight image viewer for Wayland
        pkgs.mpdas # Audio Scrobbler client for MPD
        pkgs.mpd-mpris # MPRIS 2 bridge for MPD (Go, no GUI — replaces GTK-era mpdris2)
      ]
      ++ lib.optionals (config.lib.neg.enabled "media.audio.spicetify") [
        pkgs.spicetify-cli # Spotify customization tool
      ]
      ++ lib.optionals (config.lib.neg.enabled "media.audio.listenbrainzMpd") [
        pkgs.listenbrainz-mpd # MPD -> ListenBrainz scrobbler (user unit in sys/user-services)
      ];

    # MPD Service
    # Note: MPD is enabled system-wide in modules/servers/mpd/default.nix
    # systemd.user.services.mpd is removed to avoid conflicts.

    # MPD MPRIS2 bridge: mpd-mpris (Go daemon, no config file needed)
    systemd.user.services.mpd-mpris = systemdUser.mkUserService {
      description = "MPD MPRIS2 Bridge";
      presets = [
        "defaultWanted"
        "restartOnFailure"
      ];
      serviceConfig = {
        ExecStart = lib.getExe pkgs.mpd-mpris; # Start MPD MPRIS2 bridge
      };
    };

  }

  (neg.mkHomeFiles {
    # Beets
    ".config/beets/config.yaml".text = builtins.toJSON beetsSettings;

    ".config/mpd/playlists/.keep".text = "";

    ".config/swayimg".source = config.lib.neg.live "files/gui/swayimg";

    # Spicetify Config (partial management)
    ".config/spicetify/config-xpui.ini" = lib.mkIf (config.lib.neg.enabled "media.audio.spicetify") {
      text = lib.generators.toINI { } spiceSettings;
    };

  })
  {
  }
  (lib.mkIf (config.lib.neg.pathExists "secrets/home/mpdas/neg.rc") {
    sops.secrets."mpdas_negrc" = {
      sopsFile = config.lib.neg.path "secrets/home/mpdas/neg.rc";
      format = "binary";
      owner = "neg";
    };
    # mpdas service lives in sys/user-services.nix.
  })
  # listenbrainz-mpd (MPD -> ListenBrainz, unit in sys/user-services/listenbrainz.nix):
  # the token secret does not exist yet, so secret + config.toml + unit are all
  # gated on it — enabling the feature flag without the secret is a no-op. To
  # activate: create secrets/home/listenbrainz-mpd.sops.yaml with key `token`
  # (yaml) and rebuild. See features.media.audio.listenbrainzMpd.apiUrl to feed
  # the local Koito hub (servicesProfiles.koito) instead of listenbrainz.org.
  (lib.mkIf
    (
      config.lib.neg.enabled "media.audio.listenbrainzMpd"
      && config.lib.neg.pathExists "secrets/home/listenbrainz-mpd.sops.yaml"
    )
    (
      lib.mkMerge [
        {
          sops.secrets."listenbrainz-mpd-token" = {
            sopsFile = config.lib.neg.path "secrets/home/listenbrainz-mpd.sops.yaml";
            key = "token";
            owner = "neg";
          };
        }
        (neg.mkHomeFiles {
          ".config/listenbrainz-mpd/config.toml".text = ''
            [submission]
            token_file = "${config.sops.secrets."listenbrainz-mpd-token".path}"
            api_url = "${config.features.media.audio.listenbrainzMpd.apiUrl}"

            [mpd]
            address = "127.0.0.1:6600"
          '';
        })
      ]
    )
  )
  (lib.mkIf (config.lib.neg.enabled "media.aiUpscale") (
    neg.mkHomeFiles {
      ".local/bin/ai-upscale-video" = {
        executable = true;
        text = config.lib.neg.readFile "modules/user/nix-maid/scripts/ai-upscale-video.sh";
      };
      ".local/bin/upscale-image" = {
        executable = true;
        text = config.lib.neg.readFile "modules/user/nix-maid/scripts/upscale-image.sh";
      };
      # VapourSynth script for the Alt+I vf toggle (~~/vs/ai/realesrgan.vpy). NOT in scripts/: mpv would load it as a Lua script.
      ".config/mpv/vs/ai/realesrgan.vpy".text =
        config.lib.neg.readFile "modules/user/nix-maid/scripts/realesrgan.vpy";
    }
  ))
]
