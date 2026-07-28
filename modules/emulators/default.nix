{ ... }:
{
  imports =
    builtins.readDir ./.
    |> builtins.attrNames
    |> builtins.filter (n: n != "default.nix" && n != "README.md")
    |> map (n: ./. + "/${n}");
}
