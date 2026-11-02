# Training workload for the PGO/BOLT profile: a trimmed version of
# ~/src/nix-optimized/workloads/instantiate.nix. It instantiates (evaluates,
# never builds) a set of nixpkgs attributes plus two NixOS release closures,
# which is the same code path (module system + mkDerivation + flake-free eval)
# as `nix eval .#nixosConfigurations.trantor...`.
{ nixpkgs, system }:
let
  pkgs = import nixpkgs { inherit system; };
  inherit (pkgs) lib;

  drvOf =
    x:
    let
      r = builtins.tryEval (if lib.isDerivation x then x.drvPath else null);
    in
    if r.success && r.value != null then [ r.value ] else [ ];

  attr = path: lib.attrByPath (lib.splitString "." path) null pkgs;

  apps = map attr [
    "blender"
    "firefox"
    "llvmPackages.clang"
    "python3Packages.torch"
    "qemu"
  ];

  release = import (nixpkgs + "/nixos/release.nix") { supportedSystems = [ system ]; };

  closures = lib.concatMap (name: drvOf (release.closures.${name}.${system} or null)) [
    "simple"
    "gnome"
  ];

  python = lib.concatMap drvOf (lib.attrValues pkgs.python3Packages);
in
toString (builtins.length (lib.concatMap drvOf apps ++ closures ++ python))
