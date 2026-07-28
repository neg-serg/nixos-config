{ ... }:
{
  imports =
    let
      excludes = [
        "psd"      # empty placeholder dir
        "wrappers" # empty placeholder dir
      ];
    in
      builtins.readDir ./.
      |> builtins.attrNames
      |> builtins.filter (n: n != "default.nix" && !builtins.elem n excludes)
      |> map (n: ./. + "/${n}");
}
