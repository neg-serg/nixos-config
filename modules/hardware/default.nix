# Hardware module aggregator
# Config and options moved to ./config.nix for flat-import compatibility
{ ... }:
{
  imports =
    builtins.readDir ./.
    |> builtins.attrNames
    |> builtins.filter (n: n != "default.nix")
    |> map (n: ./. + "/${n}");
}
