{ ... }:
{
  imports =
    builtins.readDir ./.
    |> builtins.attrNames
    |> builtins.filter (n: n != "default.nix")
    |> map (n: ./. + "/${n}");
}
