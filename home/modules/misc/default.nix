{lib, ...}: let
  hasModule = path:
    builtins.pathExists path
    && (
      lib.hasSuffix ".nix" (toString path)
      || builtins.pathExists (toString path + "/default.nix")
    );
  optionalPath = path: lib.optional (hasModule path) path;
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
