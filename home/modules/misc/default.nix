{lib, ...}: let
  optionalPath = path: lib.optional (builtins.pathExists path) path;
in {
  imports = [
    ./unfree.nix
    ./unfree-libretro.nix
    ./unfree-auto.nix
    ./fun-art.nix
    ./rustmission.nix
  ];
}
