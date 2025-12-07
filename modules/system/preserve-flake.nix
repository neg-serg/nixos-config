# preserve the flake that built the current system generation
{inputs, ...}: let
  inherit (inputs) self;
in {
  environment.etc."current-flake".source = self;
}
