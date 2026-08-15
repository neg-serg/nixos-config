{
  lib,
  ...
}:
{
  # nixpkgs.config.packageOverrides moved to packages/overlay.nix
  # python3-lto defined there as well
  imports =
    builtins.readDir ./.
    |> builtins.attrNames
    |> builtins.filter (n: n != "default.nix" && lib.hasSuffix ".nix" n)
    |> builtins.map (n: ./. + "/${n}");
}
