_inputs: _final: prev:

{
  swayimg = prev.swayimg;

  pipemixer = prev.callPackage ../pipemixer { };
  wiremix = prev.callPackage ../wiremix { };

  neg = (prev.neg or { });
}
