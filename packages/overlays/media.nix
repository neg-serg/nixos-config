_inputs: final: prev:

{
  swayimg = prev.callPackage ../swayimg { };
  hdspeconf = prev.callPackage ../hdspeconf { };
  waves = prev.callPackage ../waves { };
  pwroute = prev.callPackage ../pwroute { };
  pw-audioshare = prev.callPackage ../pw-audioshare { };
  genlc = prev.callPackage ../genlc-rs { };
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
  timestretch = prev.callPackage ../timestretch { }; # TimeStretch SC quark: Ness Stretch extreme time stretch
  pitchshiftpa = prev.callPackage ../pitchshiftpa { }; # PitchShiftPA SC quark: phase-aligned pitch/formant shifter
  softcut-sc = prev.callPackage ../softcut-sc { scPluginFarm = final.sc-plugin-farm; }; # monome Softcut multi-voice looper as SC UGen
  signalbox = prev.callPackage ../signalbox { }; # SignalBox SC quark: time/frequency-domain analysis tools
  crucial-library = prev.callPackage ../crucial-library { }; # crucial-library SC quark: AbstractPlayer live-coding system
  # -- analysis / spatial / VST hosting --
  scmir = prev.callPackage ../scmir { }; # SCMIR: music IR analysis library + CLI tools
  atk-sc3 = prev.callPackage ../atk-sc3 { }; # Ambisonic Toolkit SC quark
  vstplugin = prev.callPackage ../vstplugin { scPluginFarm = final.sc-plugin-farm; }; # host VST2/VST3 in scsynth
  flucoma = prev.callPackage ../flucoma { scPluginFarm = final.sc-plugin-farm; }; # FluCoMa: corpus manipulation UGens (57 plugins)
  # -- ATK dependency quarks --
  hilbert = prev.callPackage ../hilbert { }; # Hilbert transform utilities (ATK dep)
  pointview = prev.callPackage ../pointview { }; # spherical point visualization (ATK dep)
  sphericaldesign = prev.callPackage ../sphericaldesign { }; # spherical design point sets (ATK dep)
  filelog = prev.callPackage ../filelog { }; # file logging/player classes (ATK dep)
  mathlib = prev.callPackage ../mathlib { }; # math classes, matrices (ATK dep)
  wslib = prev.callPackage ../wslib { }; # lookahead patterns, DJ helpers (ATK dep)
  # -- live coding quarks --
  safetynet = prev.callPackage ../safetynet { }; # protect against dangerous audio signals
  ddwplug = prev.callPackage ../ddwplug { }; # dynamic per-note synth patching
  ddwchucklib = prev.callPackage ../ddwchucklib { }; # Chuck browser / advanced algorithmic composition
  miscellaneous-lib = prev.callPackage ../miscellaneous-lib { }; # patterns, granulation, live coding utilities
  ixiquarks = prev.callPackage ../ixiquarks { }; # GUI instruments/effects toolset
  # -- neural audio --
  nn-ar = prev.callPackage ../nn-ar { scPluginFarm = final.sc-plugin-farm; }; # nn.ar: PyTorch models in scsynth
}
