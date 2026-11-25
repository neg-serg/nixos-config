# RME HDSPe AIO Pro: hardware mixer init, default PipeWire sink, AES routing.
#
# The card runs in the "Pro" profile: 16 non-interleaved S32 channels with a
# fixed 256-frame period (which is why `default.clock.quantum` is 256 there).
# snd_hdspe initializes the hardware mixer to zeros, so without
# `hdspe-init-mixer` everything is silent even though the graph runs.
#
# Gotcha: a stuck playback DMA. If the PipeWire graph is rebuilt while a stream
# is live (seen 2026-11-19: the first client connected to the game-stereo
# loopback when Steam started), the card can stop its DMA for good. ALSA keeps
# reporting `state: RUNNING`, but hw_ptr and the card's BUF_PTR/BUF_ID stay
# frozen and the card replays its last buffer, which is audible as a looping
# fragment. CamillaDSP then starves ("Capture: waited 1s ... skipping chunk")
# and the router falls back to the direct loopback -> RME path, but the card is
# still dead, so the monitors are silent.
#
# Reloading snd_hdspe does NOT clear it: the driver comes back, the PCM starts,
# and the DMA engine never runs. Only a PCIe reset does, and that sequence
# lives next to this file: `just hdspe-reset` (hdspe/reset-dma.sh) stops the
# graph, unbinds/resets/rebinds the function (it finds the slot itself; on
# trantor it is 0000:05:00.0, `lspci -d 1d18:`), re-inits the hardware mixer,
# starts the graph and proves the result with a test tone. The order is not
# decorative: no client may hold the device across the reset, and the mixer
# init must follow it, because the driver zeroes the mixer on load.
#
# Recovery signs: the card's IRQ fires again and
# /proc/asound/card0/pcm0p/sub0/status shows hw_ptr advancing at ~48000
# frames/s. A full power cycle also works; a warm reboot may not, since it
# re-runs the same driver init that already failed.

{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.hardware.audio.hdspe or { };

  # Set HDSPe hardware mixer levels for ALL output channels at unity gain.
  # The snd-hdspe driver initializes the mixer to all zeros (silent),
  # so we need to set "Chn N" controls to 64 (unity) for audio to pass.
  hdspeMixerScript = pkgs.writeShellScript "hdspe-init-mixer" (
    builtins.readFile (pkgs.replaceVars ./hdspe/init-mixer.sh { alsaUtils = pkgs.alsa-utils; })
  );

  # Set HDSPe pro-audio output as default PipeWire sink
  # NOTE: uses bare command names (amixer/wpctl/pw-link/sed) — PATH is
  # set by the systemd service config below via config.services.pipewire.package.
  hdspeDefaultScript = pkgs.writeShellScript "wpctl-set-hdspe-default" (
    builtins.readFile ./hdspe/set-default.sh
  );

  # pwroute-aes with a startup race workaround: wireplumber creates the RME
  # sink a moment after the session starts, and pwroute then fails with
  # "RME AIO Pro sink not found" (a oneshot never retries). Wait up to 30s
  # for the sink before routing to AES.
  pwrouteAesScript = pkgs.writeShellScript "pwroute-aes-wait" (
    builtins.readFile (pkgs.replaceVars ./hdspe/aes-wait.sh { pwroute = pkgs.pwroute; })
  );

  # pwroute: switch RME AIO Pro output between an/aes/spdif/phones

  # routing config for pwroute

  routingYaml = config.lib.neg.path "files/media/hdspe-routing.yaml";
in
{
  options.hardware.audio.hdspe = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable RME HDSPe support (mixer init, default PipeWire sink, pwroute).";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install pwroute binary
    environment.systemPackages = [
      pkgs.pwroute # PipeWire audio routing tool
    ];

    # Symlink routing.yaml for pwroute
    environment.etc."audio/routing.yaml".source = routingYaml;

    # System-level: initialize HDSPe hardware mixer on boot
    systemd.services."hdspe-init-mixer" = {
      description = "Initialize RME HDSPe hardware mixer levels";
      after = [
        "alsa-store.service"
        "sound.target"
      ];
      wantedBy = [ "sound.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${hdspeMixerScript}";
      };
    };

    # User-level: set HDSPe pro-audio sink as default
    systemd.user.services."wp-hdspe-default" = {
      description = "Set RME HDSPe as default PipeWire sink";
      after = [
        "wireplumber.service"
        "pipewire.service"
      ];
      partOf = [ "wireplumber.service" ];
      # Re-run on every wireplumber start (session start AND mid-session
      # restarts): wireplumber recreates the RME ALSA sink on restart, which
      # destroys the pw-link AES routing and leaves the loopback on analog.
      wantedBy = [ "wireplumber.service" ]; # don't block default.target/maid activation
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${hdspeDefaultScript}";
        # wpctl ships with wireplumber, NOT pipewire — without it the wait
        # loop and sink parsing see empty output and routing never happens.
        Environment = "PATH=${
          lib.makeBinPath [
            config.services.pipewire.package # pw-link, pw-cli
            config.services.pipewire.wireplumber.package # wpctl
            pkgs.alsa-utils # ALSA utilities (amixer, aplay, etc.)
            pkgs.gnused # GNU sed
            pkgs.coreutils # GNU core utilities
          ]
        }";
      };
    };

    # User-level: route audio to AES output by default
    systemd.user.services."pwroute-aes" = {

      description = "Route PipeWire audio to RME AES output";
      after = [
        "wp-hdspe-default.service"
        "wireplumber.service"
        "pipewire.service"
      ];
      requires = [ "wp-hdspe-default.service" ];
      partOf = [ "wireplumber.service" ];
      wantedBy = [ "wireplumber.service" ]; # re-run whenever wireplumber restarts
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pwrouteAesScript}";
        # pwroute shells out to pw-link (pipewire); wpctl comes from
        # wireplumber; seq/sleep (coreutils) drive the wait loop. Missing
        # coreutils/wireplumber made the loop a silent no-op and pwroute
        # never ran (`seq: command not found`, `wpctl: command not found`).
        Environment = "PATH=${
          lib.makeBinPath [
            config.services.pipewire.package # pw-link, pw-cli
            config.services.pipewire.wireplumber.package # wpctl
            pkgs.coreutils # seq/sleep for the RME sink wait loop
          ]
        }";
      };
    };
  };
}
