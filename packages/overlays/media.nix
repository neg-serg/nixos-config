_inputs: _final: prev:

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
}
