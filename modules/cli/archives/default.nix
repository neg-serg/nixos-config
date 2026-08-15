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
