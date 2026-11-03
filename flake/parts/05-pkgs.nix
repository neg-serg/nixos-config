{ config, ... }:
{
  # One nixpkgs instance with the repo overlays per system. flake-parts sets a
  # legacyPackages default via mkOptionDefault; this definition wins and is
  # shared by every perSystem module.
  perSystem = { system, ... }: {
    _module.args.pkgs = config.neg.lib.mkPkgs system;
  };
}
