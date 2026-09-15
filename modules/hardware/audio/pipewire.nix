{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.hardware.audio.rnnoise or { };
  # LAN audio access (features.media.audio.lanAccess): Pulse-compatible TCP
  # server on 4713 (other devices send audio here) + RTP multicast sink
  # (this machine broadcasts audio to the LAN).
  lan = config.features.media.audio.lanAccess or { enable = false; };
in
{
  options.hardware.audio.rnnoise.enable =
    lib.mkEnableOption "Enable RNNoise-based virtual microphone (PipeWire filter-chain).";

  config = lib.mkMerge [
    {
      # Default to enabled globally; hosts can override to false
      hardware.audio.rnnoise.enable = lib.mkDefault true;

      security.rtkit.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
        jack.enable = true;
        # Base low-latency tuning + optional RNNoise virtual mic.
        # The clock/quantum settings deliberately live in ONE place: the user
        # drop-in files/media/pipewire/pipewire.conf.d/clock-rate.conf (via
        # nix-maid, modules/user/nix-maid/sys/pipewire.nix), which is parsed
        # after this file and therefore wins — it locks the graph to the RME
        # HDSPe's 48 kHz / 256-frame periods (see the comments there). Keys
        # duplicated in both files used to contradict each other (128 here vs
        # 256 there) and only the drop-in took effect; audit 2026-09-15.
        extraConfig.pipewire = {
          "92-low-latency" = {
            "context.properties" = {
              "link.max-buffers" = 16;
              "cpu.zero.denormals" = true;
              "clock.power-of-two-quantum" = true;
            };
            "stream.properties" = {
              "resample.quality" = 14;
            };
            "pulse.properties" = {
              "server.address" = [ "unix:native" ];
            };
          };
          # Harman Target sub-shelf EQ — boosts 55Hz +2.24dB for loudness compensation.
          # Ported from legacy Salt config (99-harman-subshelf.conf).
          "93-harman-eq" = {
            "context.modules" = [
              {
                name = "libpipewire-module-filter-chain";
                args = {
                  "node.description" = "Harman Sub Shelf EQ";
                  "media.name" = "Harman EQ";
                  "filter.graph" = {
                    nodes = [
                      {
                        type = "lv2";
                        name = "eq";
                        plugin = "http://lsp-plug.in/plugins/lv2/para_equalizer_x32_stereo";
                        control = {
                          "enabled" = 1;
                          "g_in" = 1.0;
                          "g_out" = 1.0;
                          "ft_0" = 5;
                          "fm_0" = 0;
                          "f_0" = 55.0;
                          "g_0" = 2.239;
                          "q_0" = 0.707;
                          "s_0" = 0;
                        };
                      }
                    ];
                    inputs = [
                      "eq:in_l"
                      "eq:in_r"
                    ];
                    outputs = [
                      "eq:out_l"
                      "eq:out_r"
                    ];
                  };
                  "capture.props" = {
                    "node.name" = "harman_shelf_sink";
                    "media.class" = "Audio/Sink";
                    "audio.channels" = 2;
                    "audio.position" = [
                      "FL"
                      "FR"
                    ];
                  };
                  "playback.props" = {
                    "node.name" = "harman_shelf_source";
                    "media.class" = "Audio/Source";
                    "audio.channels" = 2;
                    "audio.position" = [
                      "FL"
                      "FR"
                    ];
                  };
                };
              }
            ];
          };

          # Game audio virtual stereo sink is now in
          # files/media/pipewire/pipewire.conf.d/20-game-stereo.conf — a loopback
          # that creates actual playback ports (playback_FL/playback_FR) routable
          # to hardware via pw-link (see modules/hardware/audio/hdspe/default.nix).
          # The loopback is created unconditionally (no hardcoded ALSA target),
          # so it's always visible to games even before hardware ALSA nodes are up.
        }
        // lib.optionalAttrs (cfg.enable or false) {
          "95-rnnoise-filter-chain" = {
            "context.modules" = [
              {
                name = "libpipewire-module-filter-chain";
                args = {
                  "node.name" = "rnnoise_source";
                  "node.description" = "Noise Canceling (RNNoise)";
                  "media.class" = "Audio/Source";
                  "filter.graph" = {
                    nodes = [
                      {
                        type = "ladspa";
                        name = "rnnoise";
                        plugin = "${pkgs.rnnoise-plugin}/lib/ladspa/rnnoise_ladspa.so"; # Real-time noise suppression plugin for voice based on Xip...
                        label = "noise_suppressor_stereo";
                      }
                    ];
                  };
                  "capture.props" = {
                    "node.passive" = true;
                    "node.description" = "RNNoise Input";
                  };
                  "playback.props" = {
                    "node.description" = "RNNoise Source";
                  };
                };
              }
            ];
          };
        };
        wireplumber = {
          package = pkgs.wireplumber; # Modular session / policy manager for PipeWire
          extraConfig = {
            # Default volume is by default set to 0.4 instead set it to 1.0
            "10-default-volume" = {
              "wireplumber.settings"."device.routes.default-sink-volume" = 1.0;
            };
            # Never restore a stream's old target sink: wireplumber remembers
            # (stream-properties) that e.g. mpv/MPD once linked straight to the
            # RME AES pair and re-links them there on every reconnect, on top
            # of the game-stereo route -> two copies ~18ms apart -> combed,
            # muddy bass. Streams must always follow the default sink only.
            "11-no-stream-restore" = {
              "wireplumber.settings"."node.stream.restore-target" = false;
            };
          };
        };
      };
      # run pipewire on default.target, this fixes xdg-portal startup delay
      systemd.user.services.pipewire.wantedBy = [ "default.target" ];

      # WirePlumber queries UPower for battery info; make sure UPower is up first
      systemd.user.services.wireplumber.after = [ "upower.service" ];
      systemd.user.services.wireplumber.wants = [ "upower.service" ];

      # Extend LV2_PATH to include lsp-plugins (needed for Harman EQ filter-chain)
      systemd.user.services.pipewire.environment.LV2_PATH =
        lib.mkForce "${pkgs.lsp-plugins}/lib/lv2:${config.services.pipewire.package}/lib/lv2";

      # Try to make RNNoise the default source automatically once WirePlumber is up
      systemd.user.services."wp-rnnoise-default" = lib.mkIf (cfg.enable or false) (
        let
          script = pkgs.writeShellScript "wpctl-set-rnnoise-default" ''
            set -euo pipefail
            for i in $(seq 1 60); do
              if wpctl status | grep -q "rnnoise_source"; then
                wpctl set-default rnnoise_source || true
                exit 0
              fi
              sleep 0.25
            done
            exit 0
          '';
        in
        {
          description = "Set RNNoise virtual source as default (wpctl)";
          after = [
            "wireplumber.service"
            "pipewire.service"
          ];
          partOf = [ "wireplumber.service" ];
          wantedBy = [ "default.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${script}";
          };
        }
      );

    }
    # ------------------------------------------------------------------
    # LAN audio access (features.media.audio.lanAccess.enable)
    # ------------------------------------------------------------------
    (lib.mkIf (lan.enable or false) {
      services.pipewire.extraConfig = {
        # Pulse-compatible TCP server: other devices can play audio through
        # this machine (PULSE_SERVER=odin:4713 or PulseAudio-over-network).
        # Keep the unix socket — it is the local default.
        pipewire-pulse."20-network" = {
          "pulse.properties"."server.address" = [
            "unix:native"
            "tcp:4713"
          ];
        };

        # RTP multicast sink: a virtual Audio/Sink ("RTP LAN broadcast") that
        # streams anything routed to it to 224.0.0.56:46000 (LAN multicast).
        # Receivers, e.g. VLC: rtp://224.0.0.56:46000
        pipewire."94-rtp-sink" = {
          "context.modules" = [
            {
              name = "libpipewire-module-rtp-sink";
              args = {
                "local.ifname" = lan.rtp.interface;
                "destination.ip" = "224.0.0.56";
                "destination.port" = 46000;
                "net.ttl" = 1; # local subnet only
                "net.loop" = true; # also deliver to this machine (local testing)
                "sess.name" = "Odin RTP stream";
                "audio.format" = "S16BE";
                "audio.rate" = 48000;
                "audio.channels" = 2;
                "stream.props" = {
                  "node.name" = "rtp-sink";
                  "node.description" = "RTP LAN broadcast";
                  "media.class" = "Audio/Sink";
                };
              };
            }
          ];
        };
      };

      # Pulse TCP server port (RTP multicast is outgoing UDP — no rule needed)
      networking.firewall.allowedTCPPorts = lib.mkAfter [ 4713 ];
    })
  ];
}
