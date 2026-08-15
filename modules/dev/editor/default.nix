{
  lib,
  ...
}:
let
  entries = builtins.readDir ./.;
in
{
  programs.nano = {
    enable = false;
  };
  imports =
    builtins.attrNames entries
    |> builtins.filter (
      n: n != "default.nix" && (entries.${n} == "directory" || lib.hasSuffix ".nix" n)
    )
    |> builtins.map (n: ./. + "/${n}");
}
