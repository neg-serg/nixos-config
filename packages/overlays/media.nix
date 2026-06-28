_inputs: _final: prev:

{
  swayimg = prev.callPackage ../swayimg { };

  pipemixer = prev.callPackage ../pipemixer { };
  wiremix = prev.callPackage ../wiremix { };

}
