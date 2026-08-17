##
# Module: user/nix-maid/apps/supercollider
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

  superdirtStartup = ''
    s.options.numBuffers = 1024 * 1024;
    s.options.memSize = 8192 * 64;
    s.options.numWireBufs = 256;
    s.options.maxNodes = 1024 * 64;
    s.options.numOutputBusChannels = 2;
    s.options.numInputBusChannels = 2;
    s.waitForBoot {
      var userSamples = Platform.userHomeDir +/+ "src/music/tidal/samples";
      try {
        ~dirt = SuperDirt(2, s);
        // Explicit sample paths — do NOT rely on loadSoundFiles' default
        // "../../Dirt-Samples/*".resolveRelative (it resolves against the
        // document dir, which breaks once SuperDirt lives in the nix store).
        File.mkdir(userSamples);
        // loadSoundFiles expands the glob only for a plain String path,
        // so the stock bank and the user samples dir get separate calls.
        ~dirt.loadSoundFiles("${pkgs.neg.dirt-samples}/share/Dirt-Samples/*");
        if(PathName(userSamples).folders.notEmpty) {
          ~dirt.loadSoundFiles(userSamples +/+ "*")
        };
        ~dirt.start(57120, 0 ! 12);
        "SUPERDIRT READY".postln;
      } { |err| ("SuperDirt ERROR: " ++ err.what).postln; };
    };
  '';

  bootNoop = ''
    s.options.numOutputBusChannels = 2;
    s.waitForBoot { "SC server ready".postln; };
  '';

  bootTidal = ''
    :set -fno-warn-orphans -Wno-type-defaults -XMultiParamTypeClasses -XOverloadedStrings
    :set prompt ""
    import Sound.Tidal.Boot
    default (Rational, Integer, Double, Pattern String)
    tidalInst <- mkTidal
    instance Tidally where tidal = tidalInst
    :set prompt "tidal> "
    :set prompt-cont ""

    -- ==== Musical helpers ==================================================
    -- Short instrument aliases (sample folder names).
    let k  = sound "bd"      -- kick
        sn = sound "sn"      -- snare
        hh = sound "hh"      -- hi-hat
        cp = sound "cp"      -- clap
        bass = sound "bass"  -- bass synth samples
        tab = sound "tabla"  -- tabla kit

    -- Rhythm phrases (paste into `sound`).
    let fourOnFloor = "bd(4,8) sn(3,8) hh*8"
        techno      = "bd*2 sn(3,8) hh*4"
        halftime    = "bd(2,8) sn(2,8) hh*6"
        jungle      = "bd(3,8) sn(5,8) hh*6"

    -- Random groove generator: re-chooses its phrase every cycle.
    --   d1 $ randomGroove
    let randomGroove = sound (choose ["bd*2 sn*3 hh*4", "bd(3,8) sn(5,8) hh(5,8)", "bd(5,8) hh*6", "bd(2,8) cp(3,8) hh*4"])

    -- Random euclidean kick/snare: `irand` re-rolls each cycle.
    --   d1 $ randomEuclid 8
    let randomEuclid steps = euclid (irand steps) steps $ sound "bd"

    -- Ambient pad on a random minor chord (re-rolls every 4 cycles).
    --   d1 $ ambientPad
    let ambientPad = note (scale "minor" (cat ["c4", "g4", "a4", "f4"])) # sound "superpiano" # room 0.5 # size 0.8 # gain 0.6

    -- OSC params (pF, pI, pS, ...) come from Sound.Tidal.Params,
    -- re-exported by Sound.Tidal.Boot — no extra import needed.
    -- Sending to an external synth:
    --   d1 $ sound "bd" # pF "myParam" 0.5
  '';

  # SC class library config: keep default paths (SCClassLibrary + user
  # Extensions dir, where the nix SuperDirt/Vowel/SC3plugins symlinks live)
  # and add no extra include paths.
  sclangConf = ''
    includePaths: []
    excludePaths: []
    postInlineWarnings: false
    excludeDefaultPaths: false
  '';

  # Starter .tidal file for the tidal/ workspace dir.
  scratchTidal = ''
    -- TidalCycles scratch file — press <C-CR> to launch, <M-CR> to send a line
    d1 $ sound "bd sn"
    d1 $ sound "bd(3,8) sn(5,8)" # gain 0.9
    d2 $ sound "hh*4" # pan 0.5
    -- user samples: drop folders into ~/src/music/tidal/samples/,
    -- then `d1 $ sound "myname"` (folder name = sound name)
  '';

  # Multi-layer jam scene: send lines top-to-bottom, each adds a layer.
  # Run `tidalctl demo` to open it with the engine already up.
  demoTidal = ''
    -- ============ TIDAL DEMO JAM ============
    -- Send lines one by one (<M-CR>), each adds a layer.
    -- Start with drums, then bass, then chords, then melody.

    -- 1. Kicks: euclidean pattern (3 hits per 8 steps)
    d1 $ euclid 3 8 k

    -- 2. Snare on the backbeat
    d2 $ euclid 3 8 sn # delay 0.25

    -- 3. Hi-hats: steady 8ths, panned
    d3 $ euclid 4 8 hh # pan 0.5 # gain 0.5

    -- 4. Random groove generator (re-rolls every cycle!)
    d4 $ randomGroove # gain 0.7

    -- 5. Random euclidean kick (irand re-rolls each cycle)
    d1 $ randomEuclid 8

    -- 6. Bass: simple minor riff
    d5 $ note (scale "minor" "c2 d2 e2 g2") # sound "bass" # gain 0.8

    -- 7. Ambient pad on a random minor chord (re-rolls every 4 cycles)
    d6 $ ambientPad

    -- 8. Lead melody: arpeggio
    d7 $ note (arp "up" "c4'maj7") # sound "superpiano" # delay 0.3 # room 0.3

    -- 9. Everything together — add swing
    d1 $ swingBy (1/3) 4 $ euclid 3 8 k

    -- 10. Silence everything (hush: <leader>th)
    -- hush
  '';
in
{
  config = lib.mkIf enabled {
    environment.sessionVariables = {
      LD_LIBRARY_PATH = [ "${pkgs.pipewire.jack}/lib" ];
      # Server-side SC3-Plugins UGens (.so) — scsynth ищет их через SC_PLUGIN_PATH
      SC_PLUGIN_PATH = "${pkgs.supercolliderPlugins.sc3-plugins}/lib/SuperCollider/plugins";
    };
    environment.etc = {
      "skel/.config/SuperCollider/superdirt_startup.scd".text = superdirtStartup;
      "skel/.config/SuperCollider/boot_noop.scd".text = bootNoop;
    };
    users.users.neg.maid.file.home = {
      ".config/SuperCollider/superdirt_startup.scd".text = superdirtStartup;
      ".config/SuperCollider/boot_noop.scd".text = bootNoop;
      ".config/SuperCollider/sclang_conf.yaml".text = sclangConf;
      ".config/tidal/BootTidal.hs".text = bootTidal;
      # SuperDirt classes from the nix package (replaces manual quark install)
      ".local/share/SuperCollider/Extensions/SuperDirt".source =
        "${pkgs.neg.superdirt}/share/SuperCollider/extensions/SuperDirt";
      # Vowel formant tables from the nix package (SuperDirt initVowels needs it)
      ".local/share/SuperCollider/Extensions/Vowel".source =
        "${pkgs.neg.vowel}/share/SuperCollider/extensions/Vowel";
      # SC3-Plugins классы (DynKlank, SwitchDelay, …) — нужны SuperDirt default-synths
      ".local/share/SuperCollider/Extensions/SC3plugins".source =
        "${pkgs.supercolliderPlugins.sc3-plugins}/share/SuperCollider/Extensions/SC3plugins";
      # Tidal workspace: starter file + demo jam + user samples dir
      "src/music/tidal/scratch.tidal".text = scratchTidal;
      "src/music/tidal/demo.tidal".text = demoTidal;
    };
  };
}
