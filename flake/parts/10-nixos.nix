{
  inputs,
  self,
  lib,
  config,
  ...
}:
let
  flakeLib = config.neg.lib;
  pkgs = flakeLib.mkPkgs (builtins.head config.systems);
  filteredSource = lib.cleanSourceWith {
    filter = name: _type: !(lib.hasSuffix ".md" (builtins.baseNameOf name));
    src = lib.cleanSource ../../.;
  };
  nixosOut = import ../nixos.nix {
    inherit
      inputs
      self
      pkgs
      filteredSource
      ;
    inherit (inputs) nixpkgs;
  };
in
{
  options.neg.nixosOut = lib.mkOption { type = lib.types.raw; };

  config = {
    flake.nixosConfigurations = nixosOut.configurations;

    neg.nixosOut = nixosOut;
  };
}
