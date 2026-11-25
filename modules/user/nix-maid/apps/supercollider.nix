##  Module: user/nix-maid/apps/supercollider
# Purpose: SuperCollider live-coding stack (raw SC via scnvim; tidalctl and the
# nvim tidal plugin run alongside, the Tidal/GHCi toolchain itself lives in the
# `haskell` devshell and is entered through the system `tidal-ghci` wrapper).
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.features.media.audio.creation or { };
  enabled = cfg.enable or false;

  # PipeWire/JACK unit shape (lib/jack-app.nix): the pw-link watcher links
  # scsynth's out ports whenever they appear, surviving engine restarts.
  jackApp = config.lib.neg.jackApp;

  # SuperDirt and Vowel now come from nix packages (packages/superdirt,
  # packages/vowel) symlinked into SC's default extension dir below — the
  # manual `install-superdirt-quark` step is gone.
  # The startup script itself (superdirt_startup.scd) is NOT deployed here:
  # it lives in the private ~/notes/music/supercollider and is symlinked to
  # ~/.config/SuperCollider/superdirt_startup.scd, so the user can edit
  # engine code and custom synths freely.

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

  # Quark dirs for the file attrs below: every package installs its classes as
  # `share/SuperCollider/<dir>/<Name>` and is symlinked to
  # `.local/share/SuperCollider/Extensions/<Name>` (`ext`). Three packages
  # (SC3plugins, Myplugins, VSTPlugin) ship an uppercase `Extensions/`.
  ext = ".local/share/SuperCollider/Extensions";
  scExt = pkg: name: "${pkg}/share/SuperCollider/extensions/${name}";
  scExtUpper = pkg: name: "${pkg}/share/SuperCollider/Extensions/${name}";

  # Content packages are not part of the system closure: modules/media/audio/assets.nix
  # materialises them into ~/.local/state/nix-apps (login oneshot) and the
  # symlinks/env below point at those GC roots instead of at store paths.
  assetsRoot = "${config.lib.neg.homeDir}/.local/state/nix-apps";

  # Server-side UGen plugins (.so) — scsynth finds them via SC_PLUGIN_PATH
  # (colon-separated dir list: SC3-Plugins + the ported third-party plugins).
  # Used both by sessionVariables and the supercollider-engine unit env.
  scPluginPath = lib.concatStringsSep ":" [
    "${pkgs.supercolliderPlugins.sc3-plugins}/lib/SuperCollider/plugins"
    "${pkgs.music.f0plugins}/lib/SuperCollider/plugins"
    "${pkgs.music.steroids-ugens}/lib/SuperCollider/plugins"
    "${pkgs.music.super-bufrd}/lib/SuperCollider/plugins"
    "${pkgs.music.xplaybuf}/lib/SuperCollider/plugins"
    "${pkgs.music.mi-ugens}/lib/SuperCollider/plugins"
    "${pkgs.music.guttersynth-sc}/lib/SuperCollider/plugins"
    "${pkgs.music.my-ugens}/lib/SuperCollider/plugins"
    "${pkgs.music.softcut-sc}/lib/SuperCollider/plugins"
    "${pkgs.music.vstplugin}/share/SuperCollider/Extensions/VSTPlugin/plugins"
    "${assetsRoot}/flucoma/lib/SuperCollider/plugins" # FluCoMa: corpus manipulation UGens (GC root from assets.nix)
    "${pkgs.music.dwg-reverb}/lib/SuperCollider/plugins" # DWGReverb: virtual room reverb UGens
    "${pkgs.music.mdugens}/lib/SuperCollider/plugins" # MDUGens: TPTFilter/SOSBank UGens (PlateReverb etc.)
    "${pkgs.music.portedplugins}/lib/SuperCollider/plugins" # portedplugins: VA filters, Fverb reverb
    "${assetsRoot}/sc-faust/lib/SuperCollider/plugins" # sc_faust: Faust JIT compiler UGen
  ];

in
{
  config = lib.mkIf enabled {
    environment.sessionVariables = {
      LD_LIBRARY_PATH = [ "${pkgs.pipewire.jack}/lib" ];
      # Server-side UGen plugins (.so) — scsynth finds them via SC_PLUGIN_PATH
      # (defined once in the let block; shared with supercollider-engine unit)
      SC_PLUGIN_PATH = scPluginPath;
    };

    # Keep scsynth's JACK out ports linked to the game-stereo virtual sink (the
    # hdspe module routes that sink to the RME AES pair). SuperCollider runs as
    # a pipewire-jack client (LD_LIBRARY_PATH above), and pipewire-jack does NOT
    # auto-connect client ports, so without the watcher the engine is silent.
    systemd.user.services."supercollider-link" = jackApp.mkUnit {
      name = "supercollider-link";
      description = "Link SuperCollider JACK out ports to game-stereo";
      client = "SuperCollider";
      pairs = [
        {
          from = "out_1";
          to = "playback_FL";
        }
        {
          from = "out_2";
          to = "playback_FR";
        }
      ];
      sink = "game-stereo";
    };
    # No separate engine unit: the live-coding flow runs the engine inside the
    # scnvim sclang session (nvim + scnvim REPL boots scsynth itself under
    # pw-jack, see files/nvim/lua/plugins/supercollider.lua). This keeps code
    # and engine in one process so edits take effect immediately — the raw
    # SuperCollider equivalent of Tidal's hot reload, without TidalCycles.
    # SuperDirtMixer keeps its presets in the quark's own presets/ folder
    # ("../../presets/" resolved against the compiled class file path — with
    # the per-subdir symlinks above that lands in the real user dir). Make it
    # a writable dir and seed Default.json once (C copies only when missing /
    # source newer — store mtime is epoch, so user edits are never clobbered).
    systemd.user.tmpfiles.rules = [
      "d %h/.local/share/SuperCollider/Extensions/SuperDirtMixer/presets 0755 - - -"
      "C %h/.local/share/SuperCollider/Extensions/SuperDirtMixer/presets/Default.json 0644 - - - ${pkgs.music.superdirt-mixer}/share/SuperCollider/extensions/SuperDirtMixer/presets/Default.json"
    ];
    environment.etc = {
      "skel/.config/SuperCollider/boot_noop.scd".text = bootNoop;
    };
    users.users.neg.maid.file.home = {
      ".config/SuperCollider/boot_noop.scd".text = bootNoop;
      ".config/SuperCollider/sclang_conf.yaml".text = sclangConf;
      # SuperDirt classes from the nix package (replaces manual quark install)
      "${ext}/SuperDirt".source = scExt pkgs.music.superdirt "SuperDirt";
      # Vowel formant tables from the nix package (SuperDirt initVowels needs it)
      "${ext}/Vowel".source = scExt pkgs.music.vowel "Vowel";
      # SC3-Plugins classes (DynKlank, SwitchDelay, …) — needed by SuperDirt default-synths
      "${ext}/SC3plugins".source = scExtUpper pkgs.supercolliderPlugins.sc3-plugins "SC3plugins";
      # EQui — parametric EQ quark used by SuperDirtMixer (read-only code)
      "${ext}/EQui".source = scExt pkgs.music.equi "EQui";
      # JSONlib — JSON en/decoder quark used by SuperDirtMixer (read-only code)
      "${ext}/JSONlib".source = scExt pkgs.music.jsonlib "JSONlib";
      # SuperDirtMixer — graphical mixer UI for SuperDirt orbits. Subdirs are
      # symlinked individually (NOT the whole quark) so that relative paths
      # ("../../presets/", resolved by SC against the compiled class file
      # path) stay inside the real user dir and preset files remain writable;
      # the code itself is read-only in the store. The presets dir and its
      # Default.json seed come from the systemd.user.tmpfiles.rules below.
      ".local/share/SuperCollider/Extensions/SuperDirtMixer/classes".source =
        "${pkgs.music.superdirt-mixer}/share/SuperCollider/extensions/SuperDirtMixer/classes";
      ".local/share/SuperCollider/Extensions/SuperDirtMixer/synths".source =
        "${pkgs.music.superdirt-mixer}/share/SuperCollider/extensions/SuperDirtMixer/synths";
      ".local/share/SuperCollider/Extensions/SuperDirtMixer/HelpSource".source =
        "${pkgs.music.superdirt-mixer}/share/SuperCollider/extensions/SuperDirtMixer/HelpSource";
      ".local/share/SuperCollider/Extensions/SuperDirtMixer/assets".source =
        "${pkgs.music.superdirt-mixer}/share/SuperCollider/extensions/SuperDirtMixer/assets";
      ".local/share/SuperCollider/Extensions/SuperDirtMixer/tidal".source =
        "${pkgs.music.superdirt-mixer}/share/SuperCollider/extensions/SuperDirtMixer/tidal";
      ".local/share/SuperCollider/Extensions/SuperDirtMixer/SuperDirtMixer.quark".source =
        "${pkgs.music.superdirt-mixer}/share/SuperCollider/extensions/SuperDirtMixer/SuperDirtMixer.quark";
      # Dirt-Samples at a stable path — the notes startup script (which cannot
      # interpolate nix store paths) loads samples from here.
      ".local/share/SuperCollider/Dirt-Samples".source = "${assetsRoot}/dirt-samples/share/Dirt-Samples";
      # Ported third-party UGen plugin classes (.sc files; the .so plugins are
      # found via SC_PLUGIN_PATH above). Each package installs its own quark
      # layout under share/SuperCollider/extensions/<QuarkName>/.
      "${ext}/f0plugins".source = scExt pkgs.music.f0plugins "f0plugins";
      "${ext}/Steroids".source = scExt pkgs.music.steroids-ugens "Steroids";
      "${ext}/SuperBufRd".source = scExt pkgs.music.super-bufrd "SuperBufRd";
      "${ext}/XPlayBuf".source = scExt pkgs.music.xplaybuf "XPlayBuf";
      "${ext}/mi-UGens".source = scExt pkgs.music.mi-ugens "mi-UGens";
      "${ext}/DWGReverb".source = scExt pkgs.music.dwg-reverb "DWGReverb";
      "${ext}/mdugens".source = scExt pkgs.music.mdugens "mdugens";
      "${ext}/portedplugins".source = scExt pkgs.music.portedplugins "portedplugins";
      "${ext}/sc_faust".source = "${assetsRoot}/sc-faust/share/SuperCollider/extensions/sc_faust";
      "${ext}/GutterSynth".source = scExt pkgs.music.guttersynth-sc "GutterSynth";
      # MyUGens installs its classes under a shared Myplugins/ parent dir
      "${ext}/Myplugins".source = scExtUpper pkgs.music.my-ugens "Myplugins";
      "${ext}/TimeStretch".source = scExt pkgs.music.timestretch "TimeStretch";
      "${ext}/PitchShiftPA".source = scExt pkgs.music.pitchshiftpa "PitchShiftPA";
      "${ext}/Softcut".source = scExt pkgs.music.softcut-sc "Softcut";
      "${ext}/SignalBox".source = scExt pkgs.music.signalbox "SignalBox";
      "${ext}/crucial-library".source = scExt pkgs.music.crucial-library "crucial-library";
      # analysis / spatial / VST
      "${ext}/SCMIRExtensions".source = scExt pkgs.music.scmir "SCMIRExtensions";
      "${ext}/atk-sc3".source = scExt pkgs.music.atk-sc3 "atk-sc3";
      "${ext}/VSTPlugin".source = scExtUpper pkgs.music.vstplugin "VSTPlugin";
      # Renoise Redux VST3 at the standard user VST3 path (hosts scan ~/.vst3)
      ".vst3/renoise_redux.vst3".source = "${assetsRoot}/renoise-redux/lib/vst3/renoise_redux.vst3";
      # Protoplug VST2 (Lua live-coding plugins; VST2 hosts scan ~/.vst).
      # Dest names must be space-free: nix-maid's tmpfiles renderer writes
      # L+ lines without quoting, and systemd-tmpfiles splits on whitespace
      # (source store paths may contain spaces - last field is safe).
      ".vst/Lua_Protoplug_Fx.so".source = "${pkgs.music.protoplug}/lib/vst/Lua Protoplug Fx.so";
      ".vst/Lua_Protoplug_Gen.so".source = "${pkgs.music.protoplug}/lib/vst/Lua Protoplug Gen.so";
      # ATK dependency quarks
      "${ext}/Hilbert".source = scExt pkgs.music.hilbert "Hilbert";
      "${ext}/PointView".source = scExt pkgs.music.pointview "PointView";
      "${ext}/SphericalDesign".source = scExt pkgs.music.sphericaldesign "SphericalDesign";
      "${ext}/FileLog".source = scExt pkgs.music.filelog "FileLog";
      "${ext}/MathLib".source = scExt pkgs.music.mathlib "MathLib";
      # live coding quarks
      "${ext}/SafetyNet".source = scExt pkgs.music.safetynet "SafetyNet";
      "${ext}/ddwPlug".source = scExt pkgs.music.ddwplug "ddwPlug";
      "${ext}/miSCellaneous_lib".source = scExt pkgs.music.miscellaneous-lib "miSCellaneous_lib";
      "${ext}/ixiQuarks".source = scExt pkgs.music.ixiquarks "ixiQuarks";
      "${ext}/FluCoMa".source = "${assetsRoot}/flucoma/share/SuperCollider/extensions/FluCoMa";
    };
  };
}
