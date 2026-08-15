{
  lib,
  ...
}:
{
  # sing-box-tun-*.sh are data files — excluded by the .nix suffix filter
  imports =
    builtins.readDir ./.
    |> builtins.attrNames
    |> builtins.filter (n: n != "default.nix" && lib.hasSuffix ".nix" n)
    |> builtins.map (n: ./. + "/${n}");
}
