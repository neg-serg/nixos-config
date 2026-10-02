{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.gui;
  # Module-shaped systemd user units (lib/systemd-user.nix)
  systemdUser = config.lib.neg.systemdUser;
in
lib.mkIf (cfg.enable or false) {
  systemd.user.services = {
    # mpdas — Last.fm AudioScrobbler for MPD. Credentials from sops secret.
    # Last.fm geo-blocks the API for RU IPs (error 11 "Access Denied - You
    # cannot access this service" on every method), so all requests go through
    # the local SOCKS5 proxy (sing-box, 127.0.0.1:10808 — same proxy the
    # yt-dlp `yt` alias uses). Verified working end-to-end via the proxy.
    mpdas =
      lib.mkIf
        (
          (config.lib.neg.enabled "media.audio.mpd") && config.lib.neg.pathExists "secrets/home/mpdas/neg.rc"
        )
        (
          systemdUser.mkUserService {
            presets = [
              "defaultWanted"
              "restartOnFailure"
            ];
            description = "MPD AudioScrobbler (Last.fm)";
            # NOTE: deliberately NO after/wants on mpd.service here. In the user
            # session that name resolves to the mpd package's config-less unit
            # (`mpd --systemd`, no config file → "No configuration file found"),
            # NOT the real system MPD (modules/servers/mpd). mpdas connects to the
            # system MPD over TCP itself and reconnects on failure via the
            # restartOnFailure preset, so pulling in the user unit only produces
            # failed-start noise on every mpdas restart.
            after = [
              "network-online.target"
              "sing-box-proxy.service"
            ];
            wants = [ "sing-box-proxy.service" ];
            serviceConfig = {
              ExecStart = "${lib.getExe pkgs.mpdas} -c ${config.sops.secrets.mpdas_negrc.path}";
              Environment = [
                "MPD_HOST=127.0.0.1"
                "MPD_PORT=6600"
                # Last.fm API is geo-blocked from RU IPs — route HTTPS via sing-box.
                "HTTPS_PROXY=socks5h://127.0.0.1:10808"
                "ALL_PROXY=socks5h://127.0.0.1:10808"
                "NO_PROXY=127.0.0.1,localhost"
              ];
              # 10 s: the delay this unit has always used.
              RestartSec = 10;
            };
          }
        );

    # Pic dirs notifier
    "pic-dirs" = systemdUser.mkUserService {
      presets = [
        "defaultWanted"
        "restartOnFailure"
      ];
      description = "Pic dirs notification";
      unitConfig = {
        ConditionUser = "!greeter";
      };
      path = [
        pkgs.inotify-tools # Filesystem event monitor
        pkgs.zoxide # Smarter cd command
      ];
      serviceConfig = {
        ExecStart = "%h/.local/bin/pic-dirs-list";
        PassEnvironment = [
          "XDG_PICTURES_DIR"
          "XDG_DATA_HOME"
        ];
        RestartSec = "1";
      };
    };

    # sing-box proxy — SOCKS5 on 127.0.0.1:10808 for Telegram etc. (apps use
    # proxychains → this port, see user/session/chat.nix). Autostarts at login so
    # the proxy survives reboots; previously it only ran after a manual `proxy on`.
    # ExecStartPre regenerates the config from the SOPS secret on first run.
    # Manual control stays in ~/.local/bin/proxy (on|off|refresh|status|gen).
    # Independent of features.net.proxy.enable (legacy Xray system service).
    sing-box-proxy = systemdUser.mkUserService {
      presets = [
        "defaultWanted"
        "restartOnFailure"
      ];
      description = "sing-box SOCKS5 proxy (127.0.0.1:10808)";
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStartPre = "%h/.local/bin/proxy gen";
        Environment = [
          # Config uses the modern DNS format (route.default_domain_resolver +
          # client-side resolve action) — no deprecated DNS env vars needed.
          "PATH=/run/current-system/sw/bin:/run/current-system/sw/sbin"
        ];
        ExecStart = "${lib.getExe pkgs.sing-box} run -c %h/.config/sing-box-trojan/config.json";
        RestartSec = 5;
      };
    };

    # rtpmidid — RTP-MIDI (AppleMIDI) daemon: exposes ALSA sequencer ports over
    # the network. Linux MIDI (SC/glm-midi) reaches the dockur Windows VM's
    # rtpMIDI -> Genelec GLM MIDI control (see docs/howto/windows-vm-dockur.md).
    rtpmidid = systemdUser.mkUserService {
      presets = [
        "defaultWanted"
        "restartOnFailure"
      ];
      description = "RTP MIDI (AppleMIDI) daemon";
      after = [ "pipewire.service" ];
      wants = [ "pipewire.service" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.neg.rtpmidid} --ini ${config.lib.neg.path "files/rtpmidid/config.ini"}";
        RestartSec = 3;
      };
    };
  };

  # NOTE: rme-route-all removed (2026-09): it force-linked every playback
  # stream straight into RME AUX2/AUX3 every 5s, which - together with the
  # game-stereo -> AES route (pwroute-aes) - gave every app two paths to the
  # DAC (~18ms apart via the loopback) -> comb-filtered/muddy bass. Streams
  # now reach AES only via game-stereo (default sink) -> loopback -> AES.
}
