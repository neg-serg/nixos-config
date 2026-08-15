{
  lib,
  ...
}:
let
  entries = builtins.readDir ./.;
in
{
  # Flat modules + module subdirectories (rkn, vpn, zapret2, net-health)
  imports =
    builtins.attrNames entries
    |> builtins.filter (n: n != "default.nix" && (entries.${n} == "directory" || lib.hasSuffix ".nix" n))
    |> builtins.map (n: ./. + "/${n}");
}
