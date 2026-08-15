{
  lib,
  ...
}:
let
  entries = builtins.readDir ./.;
in
{
  # alkano-aio.nix is a package (callPackage from theme.nix), not a module
  imports =
    builtins.attrNames entries
    |> builtins.filter (n: n != "default.nix" && n != "alkano-aio.nix" && lib.hasSuffix ".nix" n)
    |> builtins.map (n: ./. + "/${n}");
}
