# readDir entry for the boot/ subdirectory — owns the boot sub-modules.
# (boot.nix is the flat sibling that configures boot.* itself.)
{
  lib,
  ...
}:
{
  imports =
    builtins.readDir ./.
    |> builtins.attrNames
    |> builtins.filter (n: n != "default.nix" && lib.hasSuffix ".nix" n)
    |> builtins.map (n: ./. + "/${n}");
}
