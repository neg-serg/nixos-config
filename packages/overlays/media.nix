_inputs: _final: prev:

{
  swayimg = prev.callPackage ../swayimg { };

  hdspeconf = prev.callPackage ../hdspeconf { };

  waves = prev.callPackage ../waves { };
}
