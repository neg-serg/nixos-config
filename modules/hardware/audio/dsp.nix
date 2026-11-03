#
# CamillaDSP: the DSP engine and its websocket control plane.
#
# The packages are always installed; `hardware.audio.dsp.camilladsp.enable`
# additionally runs the daemon as a user service. It starts with `--wait`,
# i.e. it claims no audio device at login and serves the websocket on
# 127.0.0.1:1234 until a config is applied from one of the control surfaces
# (aurora's `camilla` tab, `camillagui`, pycamilladsp). Applying a config is
# what opens the devices, so a broken chain cannot take the sound card down
# with the session, and `Stop` from a surface only costs a 2 s restart.
#
# Working tree: ~/camilladsp/{configs,coeffs} plus ~/camilladsp/statefile.yml.
# These are exactly the paths the packaged camillagui bakes into its own
# config (`$out/lib/camillagui/config/camillagui.yml`, which is read-only and
# not overridable without patching the package), while aurora's camilla tab
# resolves $XDG_CONFIG_HOME/camilladsp first and falls back to
# ~/camilladsp/configs — so one tree serves both. The directories are
# user-writable on purpose: both surfaces save configs and coefficients there,
# so they cannot be read-only store symlinks.
#
# Signal path: a CamillaDSP chain is capture -> filter -> playback. Playback to
# the ALSA `pipewire` device works (PipeWire mixes it into its default sink,
# the RME HDSPe). Capture has no source yet: PipeWire owns the HDSPe device
# exclusively, and the custom kernel has no ALSA loopback (CONFIG_SND_ALOOP is
# not set), so room correction / crossovers need snd-aloop enabled plus the
# matching PipeWire routing into that loopback before a config can pull audio
# through the DSP.
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

  # Kept in one place: the camillagui config above hardcodes this layout.
  dspHome = "${homeDir}/camilladsp";
in
{
  options.hardware.audio.dsp.camilladsp = {
    enable = lib.mkEnableOption "CamillaDSP daemon (websocket control plane on loopback)";

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
      description = "Port for the CamillaDSP websocket server (1234 is the upstream default).";
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
      description = "Extra command line arguments appended to the daemon's ExecStart.";
    };
  };

  config = lib.mkMerge [
    {
      # Enabled by default like the RNNoise virtual mic: the control plane is
      # harmless (loopback socket, no device until a config is applied) and
      # every surface that talks to it assumes it is there. Hosts that want the
      # packages without the daemon set this to false.
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
        "d ${dspHome}/configs 0755 - - -"
        "d ${dspHome}/coeffs 0755 - - -"
      ];

      systemd.user.services.camilladsp = systemdUser.mkUserService {
        description = "CamillaDSP audio DSP engine (websocket control plane)";
        presets = [
          "defaultWanted"
          "audioGraph"
          "restartAlways"
        ];
        serviceConfig = {
          ExecStart = lib.concatStringsSep " " (
            [
              (lib.getExe pkgs.camilladsp)
              "--address"
              cfg.address
              "--port"
              (toString cfg.port)
              "--wait"
              "--statefile"
              "${dspHome}/statefile.yml"
              "--loglevel"
              cfg.logLevel
            ]
            ++ cfg.extraArgs
          );
          RestartSec = "2s";
        };
      };
    })
  ];
}
