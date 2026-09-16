{
  pkgs,
  lib,
  mkDevShell,
  ...
}:
let
  # `base.nix` backs the `default` devshell; every other shell module maps to a
  # devshell of the same name. The space-separated string keeps the 25-name
  # list compact instead of one line per name.
  shellNames = lib.splitString " " (
    "lint tools haskell rust cpp java re infra python android qmk radicle "
    + "pentest elf graphics latex misc media virt text pro-audio web-archive db k8s wine"
  );
in
{
  default = mkDevShell (import ./base.nix { inherit pkgs lib; });
}
// lib.genAttrs shellNames (n: mkDevShell (import ./${n}.nix { inherit pkgs lib; }))
