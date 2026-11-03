{
  inputs,
  self,
  lib,
  config,
  ...
}:
let
  flakeLib = config.neg.lib;
  pkgs = flakeLib.mkPkgs "x86_64-linux";
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
  options.neg.mkPerSystem = lib.mkOption { type = lib.types.raw; };

  config = {
    flake.nixosConfigurations = nixosOut.configurations;

    neg.nixosOut = nixosOut;
    # Shared closure-builder: each per-system part declares only its own output.
    neg.mkPerSystem =
      path: system:
      import path {
        inherit
          self
          inputs
          flakeLib
          ;
        inherit (inputs) nixpkgs;
        inherit (nixosOut) mkTestHost mkSpecialArgs;
        pkgs = flakeLib.mkPkgs system;
      } system;
  };
}
