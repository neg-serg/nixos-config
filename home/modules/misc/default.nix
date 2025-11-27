{lib, ...}: let
  optionalPath = path: lib.optional (builtins.pathExists path) path;
in {
  imports =
    ./modules.nix
    ++ optionalPath ./doh
    ++ optionalPath ./fun-art
    ++ optionalPath ./rustmission
    ++ optionalPath ./transmission-daemon
    ++ optionalPath ./winboat.nix
    ++ optionalPath ./zapret;
}
