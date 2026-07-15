_inputs: _final: prev:

{
  swayimg = prev.callPackage ../swayimg { };
  hdspeconf = prev.callPackage ../hdspeconf { };
  waves = prev.callPackage ../waves { };
  pwroute = prev.callPackage ../pwroute { };
  zestbay = prev.callPackage ../zestbay { };
  pw-audioshare = prev.callPackage ../pw-audioshare { };
}
