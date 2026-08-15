# readDir entry for the boot/ subdirectory — owns the boot sub-modules.
# (boot.nix is the flat sibling that configures boot.* itself.)
{
  imports = [
    ./pkgs.nix # Nix package manager
    ./autofdo.nix
  ];
}
