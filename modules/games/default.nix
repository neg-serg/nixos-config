{ ... }:
{
  imports =
    builtins.readDir ./.
    |> builtins.attrNames
    |> builtins.filter (n: n != "default.nix")
    |> builtins.map (n: ./. + "/${n}");
}
