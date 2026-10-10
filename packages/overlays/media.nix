_inputs: final: prev:
let
  # Name-based package lookup: `pkg "swayimg"` is packages/swayimg/default.nix
  # (neg.functions.pkg walks the tree), so no call site counts `../` levels.
  functions = final.neg.functions;
  call = functions.callPkg;
  pkg = functions.pkg;

  # Shared extras, spelled once instead of in 15 argument sets.
  inherit (functions) mkScQuark;
  scPluginFarm = final.sc-plugin-farm;
in
{
  swayimg = call (pkg "swayimg") { };
  hdspeconf = call (pkg "hdspeconf") { };
  waves = call (pkg "waves") { };
  pwroute = call (pkg "pwroute") { };
  pw-audioshare = call (pkg "pw-audioshare") { };
  genlc = call (pkg "genlc-rs") { };
  # OSC bridge for Genelec SAM monitors via Python genlc (no official GLM).
  glm-osc = call (pkg "glm-osc") { };
  # MPD client for large libraries: Node backend + React UI, served on loopback.
  sola-mpd = call (pkg "sola-mpd") { };
  # Voice control for MPD: microphone -> local speech recognition -> player
  # commands. Standard library only (protocol client, capture, HTTP speech
  # clients), so the closure is Python plus whatever speech stack the host
  # enables separately.
  mpd-voice = call (pkg "mpd-voice") { };
  # Kernel module (RME HDSPe ALSA driver) — takes `kernel`; the default kernel
  # set is a placeholder, the host overrides it with the actual boot kernel.
  snd-hdspe = call (pkg "snd-hdspe") { kernel = prev.linuxPackages.kernel; };
  # Python libs for the CamillaGUI backend (camilladsp / camilladsp_plot modules)
  pycamilladsp = call (pkg "pycamilladsp") { };
  pycamilladsp-plot = call (pkg "pycamilladsp-plot") { };
  # VapourSynth NCNN (Vulkan) plugin: AI upscale/interp/denoise in VS (GPL-3)
  vsncnn = call (pkg "vsncnn") { };
  # SuperCollider third-party UGen plugins (server plugins + SC classes)
  sc-plugin-farm = call (pkg "sc-plugin-farm") { }; # fake SC source root for building UGens
  f0plugins = call (pkg "f0plugins") { inherit scPluginFarm; }; # redFrik SC plugins: sound chips, rhythms, wavesets
  steroids-ugens = call (pkg "steroids-ugens") { inherit scPluginFarm; }; # SC Steroids UGens (SSinOscFB, TDemand)
  super-bufrd = call (pkg "super-bufrd") { inherit scPluginFarm; }; # subsample-accurate buffer-reading UGens
  xplaybuf = call (pkg "xplaybuf") { inherit scPluginFarm; }; # granular playback UGen with crossfade
  mi-ugens = call (pkg "mi-ugens") { inherit scPluginFarm; }; # Mutable Instruments eurorack modules as UGens
  guttersynth-sc = call (pkg "guttersynth-sc") { inherit scPluginFarm; }; # GutterSynth: coupled duffing oscillators through modal synthesis
  my-ugens = call (pkg "my-ugens") { inherit scPluginFarm; }; # sonoro1234 MyUGens: DWG instruments, Karplus, pitch tracking
  mdugens = call (pkg "mdugens") { inherit scPluginFarm; }; # MDUGens: TPT SVF filters, SOSBank, PlateReverb/Phaser/Chorus FX
  portedplugins = call (pkg "portedplugins") { inherit scPluginFarm; }; # portedplugins: VA filters, drum synths, Fverb reverb
  sc-faust = call (pkg "sc-faust") { }; # sc_faust: JIT-compile Faust DSP in scsynth (incl. jpverb)
  timestretch = call (pkg "timestretch") { inherit mkScQuark; }; # TimeStretch SC quark: Ness Stretch extreme time stretch
  pitchshiftpa = call (pkg "pitchshiftpa") { inherit mkScQuark; }; # PitchShiftPA SC quark: phase-aligned pitch/formant shifter
  softcut-sc = call (pkg "softcut-sc") { inherit scPluginFarm; }; # monome Softcut multi-voice looper as SC UGen
  signalbox = call (pkg "signalbox") { inherit mkScQuark; }; # SignalBox SC quark: time/frequency-domain analysis tools
  crucial-library = call (pkg "crucial-library") { inherit mkScQuark; }; # crucial-library SC quark: AbstractPlayer live-coding system
  # -- analysis / spatial / VST hosting --
  scmir = call (pkg "scmir") { }; # SCMIR: music IR analysis library + CLI tools
  atk-sc3 = call (pkg "atk-sc3") { inherit mkScQuark; }; # Ambisonic Toolkit SC quark
  vstplugin = call (pkg "vstplugin") { inherit scPluginFarm; }; # host VST2/VST3 in scsynth
  flucoma = call (pkg "flucoma") { inherit scPluginFarm; }; # FluCoMa: corpus manipulation UGens (57 plugins)
  # -- ATK dependency quarks --
  hilbert = call (pkg "hilbert") { inherit mkScQuark; }; # Hilbert transform utilities (ATK dep)
  pointview = call (pkg "pointview") { inherit mkScQuark; }; # spherical point visualization (ATK dep)
  sphericaldesign = call (pkg "sphericaldesign") { inherit mkScQuark; }; # spherical design point sets (ATK dep)
  filelog = call (pkg "filelog") { inherit mkScQuark; }; # file logging/player classes (ATK dep)
  mathlib = call (pkg "mathlib") { inherit mkScQuark; }; # math classes, matrices (ATK dep)
  # -- live coding quarks --
  safetynet = call (pkg "safetynet") { inherit mkScQuark; }; # protect against dangerous audio signals
  ddwplug = call (pkg "ddwplug") { inherit mkScQuark; }; # dynamic per-note synth patching
  miscellaneous-lib = call (pkg "miscellaneous-lib") {
    inherit mkScQuark;
  }; # patterns, granulation, live coding utilities
  ixiquarks = call (pkg "ixiquarks") { inherit mkScQuark; }; # GUI instruments/effects toolset
  # -- neural audio --
  nn-ar = call (pkg "nn-ar") { inherit scPluginFarm; }; # nn.ar: PyTorch models in scsynth
}
