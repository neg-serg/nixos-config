#
# CamillaDSP: the DSP engine, its websocket control plane, and the insert that
# puts it in the signal path.
#
# The chain is real, not a control plane only:
#
#     apps -> game-stereo (the default PipeWire sink) -> camilladsp -> RME AES
#
# Both ends of the DSP config are the ALSA `pipewire` PCM, so the insert is two
# PipeWire streams and needs no ALSA loopback (this kernel has none): the
# `camilladsp-route` unit moves the links when the streams appear and restores
# the direct loopback -> RME path when they vanish (daemon down, config reload),
# so a broken DSP cannot cost the machine its sound. The device names in the
# config are therefore a contract — point an end at another device and the DSP
# stops carrying audio while the direct path takes over.
#
# The daemon starts with ~/.config/camilladsp/default.yml rather than `--wait`:
# the insert has to be up before anything is played. Configs are user state
# (the surfaces save and apply them), so default.yml is seeded once from
# ./dsp/default.yml and never replaced afterwards. The command line wins over
# the statefile's `config_path` (measured 2026-11-04: a config applied from a
# surface is forgotten on the next start, and the daemon rewrites that field
# with default.yml), so `default.yml` is the one place to tune; the statefile
# carries volume, mute and the last applied path for the surfaces only.
# `Stop` from a surface exits the daemon and the unit restarts it, i.e. the
# insert recovers by itself.
#
# The config's chunksize follows the PipeWire graph quantum (256 frames, see
# ./dsp/default.yml): the ALSA `pipewire` plugin refuses to hand out any other
# period size, so a mismatched chunksize only buys jitter and a warning per
# chunk.
#
# Layout (XDG; the packaged camillagui is patched to the same paths and aurora's
# camilla tab resolves $XDG_CONFIG_HOME/camilladsp first, so one tree serves
# both):
#
#   ~/.config/camilladsp/             configs the surfaces list and save
#   ~/.config/camilladsp/default.yml  the config the daemon starts with
#   ~/.config/camilladsp/coeffs/      FIR coefficients those configs reference
#   ~/.local/state/camilladsp/        statefile (volume, mute, last applied path)
#
# The directories are user-writable on purpose: both surfaces save configs and
# coefficients there, so they cannot be read-only store symlinks.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.audio.dsp.camilladsp;
  systemdUser = config.lib.neg.systemdUser;
  homeDir = config.lib.neg.homeDir;

  # Kept in one place: the patched camillagui config above bakes in the same
  # layout (packages/camillagui/default.nix).
  dspHome = "${homeDir}/.config/camilladsp";
  dspState = "${homeDir}/.local/state/camilladsp";
  dspConfig = "${dspHome}/default.yml";

  # First start only: the surfaces own the files afterwards, so a rebuilt
  # system must not overwrite a config the user tuned.
  seedConfig = pkgs.writeShellScript "camilladsp-seed" ''
    set -eu
    install -d -m 0755 ${dspHome} ${dspHome}/coeffs ${dspState}
    if [ ! -e ${dspConfig} ]; then
      install -m 0644 ${./dsp/default.yml} ${dspConfig}
    fi
  '';

  # Absolute tool paths: the user unit's PATH carries coreutils and systemd
  # only, not awk (see the ExecStartPre note in the service).
  routeScript = pkgs.writeShellScript "camilladsp-route" (
    builtins.readFile (
      pkgs.replaceVars ./dsp/route.sh {
        pwLink = pkgs.pipewire;
        awk = pkgs.gawk;
        grep = pkgs.gnugrep;
        sleep = pkgs.coreutils;
        date = pkgs.coreutils;
      }
    )
  );
in
{
  options.hardware.audio.dsp.camilladsp = {
    enable = lib.mkEnableOption "CamillaDSP daemon and the PipeWire <-> RME insert it feeds";

    address = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Address the CamillaDSP websocket server binds to. Loopback by default:
        the protocol has no authentication, so exposing it is a deliberate act.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 1234;
      description = ''
        Port for the CamillaDSP websocket server (1234 is the upstream default).
        camillagui's backend config is baked into its package
        (packages/camillagui/default.nix, `camilla_port: 1234`) and cannot read
        this option: moving the port here also needs that patch, or the GUI
        silently talks to nothing.
      '';
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [
        "trace"
        "debug"
        "info"
        "warn"
        "error"
        "off"
      ];
      default = "info";
      description = ''
        Log level. The daemon logs to the journal (`journalctl --user -u
        camilladsp`); it is deliberately not given `--logfile`, because the
        file would then be the only copy — journald keeps the history that
        matters when the daemon dies at startup.
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "--multithreaded" ];
      description = "Extra command line arguments appended to the daemon's ExecStart (before the config path).";
    };
  };

  config = lib.mkMerge [
    {
      # Enabled by default like the RNNoise virtual mic: this is the machine's
      # playback chain, and every surface that talks to the DSP assumes it is
      # there. Hosts without the insert set this to false — the packages stay.
      hardware.audio.dsp.camilladsp.enable = lib.mkDefault true;

      environment.systemPackages = [
        pkgs.brutefir # digital convolution engine for audio processing
        pkgs.camilladsp # flexible audio DSP engine for HTTP control
        pkgs.camillagui # web GUI for CamillaDSP (backend + prebuilt React frontend)
        pkgs.lsp-plugins # Linux Studio Plugins collection
        pkgs.yabridge # modern and transparent VST bridge
        pkgs.yabridgectl # command-line tool for managing yabridge VSTs
      ];
    }

    (lib.mkIf cfg.enable {
      # The writable control-plane tree. tmpfiles runs at login, so the
      # directories exist even when only camillagui or aurora is started (the
      # GUI aborts on startup when its config_dir is missing).
      systemd.user.tmpfiles.rules = [
        "d ${dspHome} 0755 - - -"
        "d ${dspHome}/coeffs 0755 - - -"
        "d ${dspState} 0755 - - -"
      ];

      systemd.user.services.camilladsp = systemdUser.mkUserService {
        description = "CamillaDSP audio DSP engine (control plane + insert)";
        presets = [
          "defaultWanted"
          "audioGraph"
          "restartAlways"
        ];
        # The daemon has to come back on its own: a WirePlumber restart takes the
        # streams away and it exits, and a config that fails to load makes every
        # start a failure. With the default 5 starts / 10 s limit and a 2 s
        # delay, ~8 s of that parks the unit as failed for good — the router
        # keeps the direct path alive meanwhile, so nothing is heard, but the
        # DSP is gone until someone restarts it by hand. Unlimited starts.
        unitConfig.StartLimitIntervalSec = 0;
        serviceConfig = {
          # The insert is a hard real-time client of the graph: every 5.33 ms
          # (quantum 256 at 48 kHz) this process has to move 256 frames through
          # both ALSA `pipewire` PCMs. Under CPU load its default SCHED_OTHER
          # threads miss that deadline: measured with 64 CPU hogs and a tone,
          # 20 xruns in 14 s on the capture stream, and at ~3x oversubscription
          # the PCM returns -EIO from snd_pcm_wait, which CamillaDSP treats as
          # fatal ("Playback error"). The daemon then exits, the router flips
          # to the direct path, and systemd restarts it — an audible gap.
          # At FIFO 19 the same test gave 7 xruns and no crash. 19 stays below
          # PipeWire's own audio threads (the server data loop is FIFO 20 via
          # rtkit) and far below the HDSPe IRQ thread (50), so the graph still
          # wins; the user manager's RLIMIT_RTPRIO is 95. Threads created by
          # the daemon inherit this policy.
          CPUSchedulingPolicy = "fifo";
          CPUSchedulingPriority = 19;
          # A period's worth of page faults is enough to miss the deadline, and
          # the pipeline has been seen partially swapped (2.5 MB peak swap).
          MemoryLock = true;
          ExecStartPre = seedConfig;
          ExecStart = lib.concatStringsSep " " (
            [
              (lib.getExe pkgs.camilladsp)
              "--address"
              cfg.address
              "--port"
              (toString cfg.port)
              "--statefile"
              "${dspState}/statefile.yml"
              "--loglevel"
              cfg.logLevel
            ]
            ++ cfg.extraArgs
            ++ [ dspConfig ]
          );
          RestartSec = "2s";
        };
      };

      systemd.user.services.camilladsp-route = systemdUser.mkUserService {
        description = "CamillaDSP insert router (game-stereo -> DSP -> RME AES)";
        presets = [
          "defaultWanted"
          "audioGraph"
          "restartAlways"
        ];
        after = [ "camilladsp.service" ];
        serviceConfig = {
          ExecStart = routeScript;
          RestartSec = "2s";
        };
      };
    })
  ];
}
