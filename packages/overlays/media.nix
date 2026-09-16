_inputs: final: prev:

{
  swayimg = prev.callPackage ../swayimg { };
  hdspeconf = prev.callPackage ../hdspeconf { };
  waves = prev.callPackage ../waves { };
  pwroute = prev.callPackage ../pwroute { };
  pw-audioshare = prev.callPackage ../pw-audioshare { };
  genlc = prev.callPackage ../genlc-rs { };
  # OSC bridge for Genelec SAM monitors via Python genlc (no official GLM).
  glm-osc = prev.callPackage ../glm-osc { };
  # Kernel module (RME HDSPe ALSA driver) — takes `kernel`; the default kernel
  # set is a placeholder, the host overrides it with the actual boot kernel.
  snd-hdspe = prev.callPackage ../snd-hdspe { kernel = prev.linuxPackages.kernel; };
  # Python libs for the CamillaGUI backend (camilladsp / camilladsp_plot modules)
  pycamilladsp = prev.callPackage ../pycamilladsp { };
  pycamilladsp-plot = prev.callPackage ../pycamilladsp-plot { };
  # VapourSynth NCNN (Vulkan) plugin: AI upscale/interp/denoise in VS (GPL-3)
  vsncnn = prev.callPackage ../vsncnn { };
  # SuperCollider third-party UGen plugins (server plugins + SC classes)
  sc-plugin-farm = prev.callPackage ../sc-plugin-farm { }; # fake SC source root for building UGens
  f0plugins = prev.callPackage ../f0plugins { scPluginFarm = final.sc-plugin-farm; }; # redFrik SC plugins: sound chips, rhythms, wavesets
  steroids-ugens = prev.callPackage ../steroids-ugens { scPluginFarm = final.sc-plugin-farm; }; # SC Steroids UGens (SSinOscFB, TDemand)
  super-bufrd = prev.callPackage ../super-bufrd { scPluginFarm = final.sc-plugin-farm; }; # subsample-accurate buffer-reading UGens
  xplaybuf = prev.callPackage ../xplaybuf { scPluginFarm = final.sc-plugin-farm; }; # granular playback UGen with crossfade
  mi-ugens = prev.callPackage ../mi-ugens { scPluginFarm = final.sc-plugin-farm; }; # Mutable Instruments eurorack modules as UGens
  guttersynth-sc = prev.callPackage ../guttersynth-sc { scPluginFarm = final.sc-plugin-farm; }; # GutterSynth: coupled duffing oscillators through modal synthesis
  my-ugens = prev.callPackage ../my-ugens { scPluginFarm = final.sc-plugin-farm; }; # sonoro1234 MyUGens: DWG instruments, Karplus, pitch tracking
  mdugens = prev.callPackage ../mdugens { scPluginFarm = final.sc-plugin-farm; }; # MDUGens: TPT SVF filters, SOSBank, PlateReverb/Phaser/Chorus FX
  portedplugins = prev.callPackage ../portedplugins { scPluginFarm = final.sc-plugin-farm; }; # portedplugins: VA filters, drum synths, Fverb reverb
  sc-faust = prev.callPackage ../sc-faust { }; # sc_faust: JIT-compile Faust DSP in scsynth (incl. jpverb)
  timestretch = prev.callPackage ../timestretch { inherit (final.neg.functions) mkScQuark; }; # TimeStretch SC quark: Ness Stretch extreme time stretch
  pitchshiftpa = prev.callPackage ../pitchshiftpa { inherit (final.neg.functions) mkScQuark; }; # PitchShiftPA SC quark: phase-aligned pitch/formant shifter
  softcut-sc = prev.callPackage ../softcut-sc { scPluginFarm = final.sc-plugin-farm; }; # monome Softcut multi-voice looper as SC UGen
  signalbox = prev.callPackage ../signalbox { inherit (final.neg.functions) mkScQuark; }; # SignalBox SC quark: time/frequency-domain analysis tools
  crucial-library = prev.callPackage ../crucial-library { inherit (final.neg.functions) mkScQuark; }; # crucial-library SC quark: AbstractPlayer live-coding system
  # -- analysis / spatial / VST hosting --
  scmir = prev.callPackage ../scmir { }; # SCMIR: music IR analysis library + CLI tools
  atk-sc3 = prev.callPackage ../atk-sc3 { inherit (final.neg.functions) mkScQuark; }; # Ambisonic Toolkit SC quark
  vstplugin = prev.callPackage ../vstplugin { scPluginFarm = final.sc-plugin-farm; }; # host VST2/VST3 in scsynth
  flucoma = prev.callPackage ../flucoma { scPluginFarm = final.sc-plugin-farm; }; # FluCoMa: corpus manipulation UGens (57 plugins)
  # -- ATK dependency quarks --
  hilbert = prev.callPackage ../hilbert { inherit (final.neg.functions) mkScQuark; }; # Hilbert transform utilities (ATK dep)
  pointview = prev.callPackage ../pointview { inherit (final.neg.functions) mkScQuark; }; # spherical point visualization (ATK dep)
  sphericaldesign = prev.callPackage ../sphericaldesign { inherit (final.neg.functions) mkScQuark; }; # spherical design point sets (ATK dep)
  filelog = prev.callPackage ../filelog { inherit (final.neg.functions) mkScQuark; }; # file logging/player classes (ATK dep)
  mathlib = prev.callPackage ../mathlib { inherit (final.neg.functions) mkScQuark; }; # math classes, matrices (ATK dep)
  # -- live coding quarks --
  safetynet = prev.callPackage ../safetynet { inherit (final.neg.functions) mkScQuark; }; # protect against dangerous audio signals
  ddwplug = prev.callPackage ../ddwplug { inherit (final.neg.functions) mkScQuark; }; # dynamic per-note synth patching
  miscellaneous-lib = prev.callPackage ../miscellaneous-lib {
    inherit (final.neg.functions) mkScQuark;
  }; # patterns, granulation, live coding utilities
  ixiquarks = prev.callPackage ../ixiquarks { inherit (final.neg.functions) mkScQuark; }; # GUI instruments/effects toolset
  # -- neural audio --
  nn-ar = prev.callPackage ../nn-ar { scPluginFarm = final.sc-plugin-farm; }; # nn.ar: PyTorch models in scsynth
}
