##  Module: user/nix-maid/apps/supercollider
# Purpose: TidalCycles one-click launch.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.features.media.audio.creation or { };
  enabled = cfg.enable or false;

  # SuperDirt and Vowel now come from nix packages (packages/superdirt,
  # packages/vowel) symlinked into SC's default extension dir below — the
  # manual `install-superdirt-quark` step is gone.
  # The startup script itself (superdirt_startup.scd) is NOT deployed here:
  # it lives in the private ~/notes/music/supercollider and is symlinked by
  # tidalctl, so the user can edit engine code and custom synths freely.

  bootNoop = ''
    s.options.numOutputBusChannels = 2;
    s.waitForBoot { "SC server ready".postln; };
  '';

  sclangConf = ''
    includePaths: []
    excludePaths: []
    postInlineWarnings: false
    excludeDefaultPaths: false
  '';

  # SuperCollider runs as a pipewire-jack client (LD_LIBRARY_PATH above), but
  # pipewire-jack does NOT auto-connect client ports and WirePlumber ignores
  # JACK nodes (they carry no media.class) — so scsynth's out ports stay
  # unlinked and Tidal is silent. This watcher links SuperCollider:out_1/2 →
  # game-stereo (the hdspe module routes that sink to the RME AES pair)
  # whenever the ports appear, surviving engine restarts.
  supercolliderLinkScript = pkgs.writeShellScript "supercollider-link" ''
    set -u
    while true; do
      if [[ "$(pw-link -o 2>/dev/null)" == *"SuperCollider:out_1"* ]]; then
        pw-link SuperCollider:out_1 game-stereo:playback_FL 2>/dev/null || true
        pw-link SuperCollider:out_2 game-stereo:playback_FR 2>/dev/null || true
      fi
      sleep 2
    done
  '';

in
{
  config = lib.mkIf enabled {
    environment.sessionVariables = {
      LD_LIBRARY_PATH = [ "${pkgs.pipewire.jack}/lib" ];
      # Server-side SC3-Plugins UGens (.so) — scsynth finds them via SC_PLUGIN_PATH
      SC_PLUGIN_PATH = "${pkgs.supercolliderPlugins.sc3-plugins}/lib/SuperCollider/plugins";
    };

    # Keep scsynth's JACK out ports linked to the game-stereo virtual sink.
    systemd.user.services."supercollider-link" = {
      description = "Link SuperCollider JACK out ports to game-stereo";
      after = [
        "pipewire.service"
        "wireplumber.service"
      ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        ExecStart = "${supercolliderLinkScript}";
        Environment = "PATH=${
          lib.makeBinPath [
            config.services.pipewire.package # pw-link
            pkgs.coreutils # sleep
          ]
        }";
      };
    };
    # SuperDirtMixer keeps its presets in the quark's own presets/ folder
    # ("../../presets/" resolved against the compiled class file path — with
    # the per-subdir symlinks above that lands in the real user dir). Make it
    # a writable dir and seed Default.json once (C copies only when missing /
    # source newer — store mtime is epoch, so user edits are never clobbered).
    systemd.user.tmpfiles.rules = [
      "d %h/.local/share/SuperCollider/Extensions/SuperDirtMixer/presets 0755 - - -"
      "C %h/.local/share/SuperCollider/Extensions/SuperDirtMixer/presets/Default.json 0644 - - - ${pkgs.neg.superdirt-mixer}/share/SuperCollider/extensions/SuperDirtMixer/presets/Default.json"
    ];
    environment.etc = {
      "skel/.config/SuperCollider/boot_noop.scd".text = bootNoop;
    };
    users.users.neg.maid.file.home = {
      ".config/SuperCollider/boot_noop.scd".text = bootNoop;
      ".config/SuperCollider/sclang_conf.yaml".text = sclangConf;
      # SuperDirt classes from the nix package (replaces manual quark install)
      ".local/share/SuperCollider/Extensions/SuperDirt".source =
        "${pkgs.neg.superdirt}/share/SuperCollider/extensions/SuperDirt";
      # Vowel formant tables from the nix package (SuperDirt initVowels needs it)
      ".local/share/SuperCollider/Extensions/Vowel".source =
        "${pkgs.neg.vowel}/share/SuperCollider/extensions/Vowel";
      # SC3-Plugins classes (DynKlank, SwitchDelay, …) — needed by SuperDirt default-synths
      ".local/share/SuperCollider/Extensions/SC3plugins".source =
        "${pkgs.supercolliderPlugins.sc3-plugins}/share/SuperCollider/Extensions/SC3plugins";
      # EQui — parametric EQ quark used by SuperDirtMixer (read-only code)
      ".local/share/SuperCollider/Extensions/EQui".source =
        "${pkgs.neg.equi}/share/SuperCollider/extensions/EQui";
      # JSONlib — JSON en/decoder quark used by SuperDirtMixer (read-only code)
      ".local/share/SuperCollider/Extensions/JSONlib".source =
        "${pkgs.neg.jsonlib}/share/SuperCollider/extensions/JSONlib";
      # SuperDirtMixer — graphical mixer UI for SuperDirt orbits. Subdirs are
      # symlinked individually (NOT the whole quark) so that relative paths
      # ("../../presets/", resolved by SC against the compiled class file
      # path) stay inside the real user dir and preset files remain writable;
      # the code itself is read-only in the store. The presets dir and its
      # Default.json seed come from the systemd.user.tmpfiles.rules below.
      ".local/share/SuperCollider/Extensions/SuperDirtMixer/classes".source =
        "${pkgs.neg.superdirt-mixer}/share/SuperCollider/extensions/SuperDirtMixer/classes";
      ".local/share/SuperCollider/Extensions/SuperDirtMixer/synths".source =
        "${pkgs.neg.superdirt-mixer}/share/SuperCollider/extensions/SuperDirtMixer/synths";
      ".local/share/SuperCollider/Extensions/SuperDirtMixer/HelpSource".source =
        "${pkgs.neg.superdirt-mixer}/share/SuperCollider/extensions/SuperDirtMixer/HelpSource";
      ".local/share/SuperCollider/Extensions/SuperDirtMixer/assets".source =
        "${pkgs.neg.superdirt-mixer}/share/SuperCollider/extensions/SuperDirtMixer/assets";
      ".local/share/SuperCollider/Extensions/SuperDirtMixer/tidal".source =
        "${pkgs.neg.superdirt-mixer}/share/SuperCollider/extensions/SuperDirtMixer/tidal";
      ".local/share/SuperCollider/Extensions/SuperDirtMixer/SuperDirtMixer.quark".source =
        "${pkgs.neg.superdirt-mixer}/share/SuperCollider/extensions/SuperDirtMixer/SuperDirtMixer.quark";
      # Dirt-Samples at a stable path — the notes startup script (which cannot
      # interpolate nix store paths) loads samples from here.
      ".local/share/SuperCollider/Dirt-Samples".source = "${pkgs.neg.dirt-samples}/share/Dirt-Samples";
    };
  };
}
