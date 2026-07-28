{ ... }:
{
  imports =
    let
      excludes = [ "scripts" ]; # helper scripts, not a NixOS module
    in
      builtins.readDir ./.
      |> builtins.attrNames
      |> builtins.filter (n: n != "default.nix" && n != "README.md" && !builtins.elem n excludes)
      |> map (n: ./. + "/${n}");
}
