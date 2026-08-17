##
# Module: servers/mpd
# Purpose: MPD profile; opens port 6600 when enabled.
# Key options: cfg = config.servicesProfiles.mpd.enable
# Dependencies: Requires user (myUser) and pkgs.
{
  lib,
  config,
  ...
}:
let
  cfg = config.features.media.audio.mpd or { enable = false; };
  # LAN access: with features.media.audio.lanAccess enabled, MPD listens on
  # all interfaces so LAN clients (mpc, mobile apps) can connect directly.
  lanAccess = config.features.media.audio.lanAccess.enable or false;
  myUser = config.users.main.name or "neg";
  myUID = config.users.main.uid or 1000;
  myGroup =
    let
      g = config.users.main.group or null;
    in
    if g == null then myUser else g;
  # Avoid module eval cycles: assume default home path
  myHome = "/home/${myUser}";
in
{
  config = lib.mkIf cfg.enable {
    systemd.services.mpd.serviceConfig = {
      Environment = "XDG_RUNTIME_DIR=/run/user/${builtins.toString myUID}";
      # Hardening
      ProtectSystem = "strict";
      PrivateTmp = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
    };

    services.mpd = {
      enable = true;
      user = myUser;
      group = myGroup;

      # Socket-activate MPD so it only starts on first client connect
      startWhenNeeded = true;
      dataDir = "${myHome}/.config/mpd";
      openFirewall = true;

      settings = {
        music_directory = "${myHome}/music";
        # "any" = all interfaces (LAN access); otherwise loopback only.
        # The systemd socket unit follows this value (startWhenNeeded).
        bind_to_address = if lanAccess then "any" else "127.0.0.1";
        port = 6600;
        log_file = "/dev/null";
        max_output_buffer_size = 131072;
        max_connections = 100;
        connection_timeout = 864000;
        restore_paused = "yes";
        save_absolute_paths_in_playlists = "yes";
        follow_inside_symlinks = "yes";
        replaygain = "off";
        auto_update = "no";
        # Use a per-application (software) mixer so MPD can
        # control volume independently of the system master.
        mixer_type = "software";

        # Show up as a separate application stream
        # in Pulse/ PipeWire mixers (own slider)
        audio_output = [
          {
            type = "pulse";
            name = "PipeWire (Pulse)";
          }
          {
            type = "fifo";
            name = "my_fifo";
            path = "/tmp/mpd.fifo";
            format = "44100:16:2";
          }
        ];
      };
    };

  };
}
