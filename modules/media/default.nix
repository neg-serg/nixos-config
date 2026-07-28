{ ... }:
{
  imports =
    let
      excludes = [ "scripts" ]; # helper scripts, not a NixOS module
    in
      builtins.readDir ./.
      |> builtins.attrNames
      |> builtins.filter (n: n != "default.nix" && !builtins.elem n excludes)
      |> map (n: ./. + "/${n}");
}
