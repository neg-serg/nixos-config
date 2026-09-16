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

  # podman pasta --config-net copies ALL host net1 addresses (incl. the .88
  # alias) into the dockur container netns, shadowing the host alias and
  # breaking the VM's proxy path (.88:10812). Remove the shadow after the
  # container starts; idempotent when the address is absent.
  ensureVmProxyAlias = pkgs.writeShellScript "ensure-vm-proxy-alias" ''
    if ${lib.getExe pkgs.podman} container exists windows 2>/dev/null; then
      ${lib.getExe pkgs.podman} exec windows ip addr del 192.168.2.88/24 dev net1 2>/dev/null || true
    fi
  '';
in
lib.mkIf (cfg.enable or false) {
  # User systemd services

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
        {
          description = "MPD AudioScrobbler (Last.fm)";
          # NOTE: deliberately NO after/wants on mpd.service here. In the user
          # session that name resolves to the mpd package's config-less unit
          # (`mpd --systemd`, no config file → "No configuration file found"),
          # NOT the real system MPD (modules/servers/mpd). mpdas connects to the
          # system MPD over TCP itself and reconnects on failure via
          # Restart=on-failure below, so pulling in the user unit only produces
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
            Restart = "on-failure";
            RestartSec = 10;
          };
          wantedBy = [ "default.target" ];
        };

    # Pic dirs notifier
    "pic-dirs" = systemdUser.mkUserService {
      presets = [ "defaultWanted" ];
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
        Restart = "on-failure";
        RestartSec = "1";
      };
    };

    # sing-box proxy — SOCKS5 on 127.0.0.1:10808 for Telegram etc. (apps use
    # proxychains → this port, see user/session/chat.nix). Autostarts at login so
    # the proxy survives reboots; previously it only ran after a manual `proxy on`.
    # ExecStartPre regenerates the config from the SOPS secret on first run.
    # Manual control stays in ~/.local/bin/proxy (on|off|refresh|status|gen).
    # Independent of features.net.proxy.enable (legacy Xray system service).
    sing-box-proxy = {
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
        Restart = "on-failure";
        RestartSec = 5;
      };
      wantedBy = [ "default.target" ];
    };

    # rtpmidid — RTP-MIDI (AppleMIDI) daemon: exposes ALSA sequencer ports over
    # the network. Linux MIDI (SC/glm-midi) reaches the dockur Windows VM's
    # rtpMIDI -> Genelec GLM MIDI control (see docs/howto/windows-vm-dockur.md).
    rtpmidid = {
      description = "RTP MIDI (AppleMIDI) daemon";
      after = [ "pipewire.service" ];
      wants = [ "pipewire.service" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.neg.rtpmidid} --ini ${config.lib.neg.path "files/rtpmidid/config.ini"}";
        Restart = "on-failure";
        RestartSec = 3;
      };
      wantedBy = [ "default.target" ];
    };

    # glm-osc — OSC bridge for Genelec SAM monitors (volume/mute/power/status
    # via Python genlc over the GLM USB adapter, no official GLM required).
    # Listen: UDP 127.0.0.1:9000; map in docs/howto/windows-vm-dockur.md.
    glm-osc = systemdUser.mkUserService {
      presets = [ "defaultWanted" ];
      description = "OSC bridge for Genelec SAM monitors";
      serviceConfig = {
        ExecStart = "${pkgs.glm-osc}/bin/glm-osc-server";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # glm-midi-relay — one-way MIDI relay to the dockur Windows VM: the VM's
    # bridge (oem/glm-midi-bridge.ps1) connects OUT to :9003 (VM-initiated TCP
    # is the only bidirectional host<->VM channel under the same-IP pasta
    # topology, unlike RTP-MIDI UDP); local glm-midi feeds 127.0.0.1:9004.
    glm-midi-relay = systemdUser.mkUserService {
      presets = [ "defaultWanted" ];
      description = "MIDI relay to the dockur Windows VM";
      serviceConfig = {
        # Script shebang is /usr/bin/env python3, which is not in the minimal
        # user-service PATH — call the interpreter explicitly.
        ExecStart = "${lib.getExe pkgs.python3} %h/.local/bin/glm-midi-relay";
        Restart = "on-failure";
        RestartSec = 3;
        # Log every forwarded packet (what the wheel sends) to /tmp/glm-relay.log.
        Environment = [ "GLM_RELAY_LOG=/tmp/glm-relay.log" ];
      };
    };

    # glm-adapter-auto — self-heal the GLM adapter placement: if the dockur
    # VM is running but the adapter got stuck on the host (usbhid bound), move
    # it back into the VM (NOPASSWD via glm-adapter-priv). Idempotent no-op
    # when the adapter is already inside the VM or the VM is stopped.
    glm-adapter-auto = {
      description = "Auto-attach the GLM adapter to the dockur VM when needed";
      serviceConfig = {
        Type = "oneshot";
        # bash explicitly: the user-service environment has no PATH, so the
        # script's #!/usr/bin/env bash shebang would fail (status 127).
        # The default NixOS user-service PATH has only coreutils/grep/sed —
        # the script also needs awk/podman/docker/genlc/lsusb/ss/sudo.
        ExecStart = "${lib.getExe pkgs.bash} %h/.local/bin/glm-adapter attach";
        Environment = [
          "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/home/neg/.local/bin:/usr/bin:/bin"
        ];
      };
    };

    # ensure-vm-proxy-alias — one-shot cleanup for the dockur Windows VM's
    # network: podman pasta --config-net copies the host's .88 alias into the
    # container netns, shadowing it, so the VM's proxy (.88:10812) dies inside
    # the container. Re-applied on a short timer (container is started
    # manually, not as a systemd unit).
    ensure-vm-proxy-alias = {
      description = "Remove host .88 alias from dockur container netns";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = ensureVmProxyAlias;
      };
    };

    # OpenRGB daemon — starts the SDK server so clients (profile service, GUI) can connect.
    # The profile is NOT loaded on daemon startup (it may not exist yet); the
    # openrgb-profile oneshot applies the saved "neg" profile after the server is ready.
    openrgb = {
      description = "OpenRGB SDK server";
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.openrgb} --server"; # SDK server for RGB control
        Restart = "on-failure";
        RestartSec = "30";
      };
      wantedBy = [ "graphical-session.target" ];
    };

    # OpenRGB profile — applies saved "neg" profile after daemon starts.
    # If no profile has been saved yet (first run), this will produce a "Profile
    # failed to load" message but does NOT fail the unit — status=0 is expected.
    # Save a profile named "neg" via the GUI or CLI to make this effective.
    # Both the server and this applier SEGV if they enumerate i2c devices
    # concurrently at session start, so wait for the server to settle, then
    # retry a few times before giving up.
    openrgb-profile = {
      description = "Apply OpenRGB neg profile";
      after = [ "openrgb.service" ];
      requires = [ "openrgb.service" ];
      startLimitIntervalSec = 120;
      startLimitBurst = 6;
      serviceConfig = {
        Type = "oneshot";
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 10";
        ExecStart = "${lib.getExe pkgs.openrgb} -p %h/.config/openrgb/neg.orp";
        RemainAfterExit = false;
        Restart = "on-failure";
        RestartSec = 10;
      };
      wantedBy = [ "graphical-session.target" ];
    };

    # Local AI (Ollama) — user-level fallback for hosts WITHOUT the system
    # ollama service (which binds the same 11434 port and serves the same
    # store). Models live on the zero pool, never on the system disk.
    "local-ai" =
      lib.mkIf ((config.lib.neg.enabled "llm") && !(config.services.ollama.enable or false))
        {
          description = "Local AI (Ollama)";
          serviceConfig = {
            ExecStart = "${lib.getExe pkgs.ollama} serve"; # Get up and running with large language models locally
            Environment = [
              # For LocalAI compatibility
              "MODELS_PATH=/zero/ai/localai"
              # Effective for Ollama
              "OLLAMA_MODELS=/zero/ai/ollama"
              "OLLAMA_HOST=127.0.0.1:11434"
            ];
            Restart = "on-failure";
            RestartSec = "2s";
          };
          wantedBy = [ "default.target" ];
        };

    # Udiskie (Automounter)
    udiskie = {
      description = "Udiskie automounter";
      serviceConfig = {
        ExecStart = "${lib.getExe' pkgs.udiskie "udiskie"} --no-tray"; # Removable disk automounter for udisks
        # Wayland-specific environment
        Environment = [
          "QT_QPA_PLATFORM=wayland"
          "XDG_SESSION_TYPE=wayland"
        ];
        Restart = "on-failure";
        RestartSec = "2";
      };
      wantedBy = [ "graphical-session.target" ];
    };

  };

  # Self-healing timer for ensure-vm-proxy-alias: the dockur container is
  # started manually, so re-check periodically (cheap, idempotent).
  systemd.user.timers.ensure-vm-proxy-alias = {
    description = "Periodic VM proxy alias cleanup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "20s";
      OnUnitActiveSec = "30s";
      Unit = "ensure-vm-proxy-alias.service";
    };
  };

  # Self-healing timer for glm-adapter-auto: keep the adapter inside the VM
  # whenever the VM runs (cheap idempotent check every 60s).
  systemd.user.timers.glm-adapter-auto = {
    description = "Periodic GLM adapter placement check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "60s";
      Unit = "glm-adapter-auto.service";
    };
  };

  # NOTE: rme-route-all removed (2026-09): it force-linked every playback
  # stream straight into RME AUX2/AUX3 every 5s, which - together with the
  # game-stereo -> AES route (pwroute-aes) - gave every app two paths to the
  # DAC (~18ms apart via the loopback) -> comb-filtered/muddy bass. Streams
  # now reach AES only via game-stereo (default sink) -> loopback -> AES.

  # Restart quickshell when its config is redeployed: nh os switch restarts
  # the shell BEFORE nix-maid activation updates the config symlinks, so the
  # running shell keeps the OLD code until manually restarted. Watching the
  # shell.qml symlink catches the flip and reloads the new config.
  systemd.user.paths.quickshell-config = {
    description = "Restart quickshell when its config changes";
    wantedBy = [ "paths.target" ];
    pathConfig = {
      PathChanged = "/home/neg/.config/quickshell/shell.qml";
      Unit = "quickshell.service";
    };
  };
}
