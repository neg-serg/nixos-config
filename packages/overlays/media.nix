_inputs: _final: prev:

{
  swayimg = prev.callPackage ../swayimg { };

  wiremix = prev.callPackage ../wiremix { };

  hdspeconf = prev.callPackage ../hdspeconf { };

  waves = prev.callPackage ../waves { };
}
