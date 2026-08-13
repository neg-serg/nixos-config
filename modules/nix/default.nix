{ ... }:
{
  imports =
    let
      excludes = [
        "caches.data.nix" # data file, not a module
      ];
    in
    builtins.readDir ./.
    |> builtins.attrNames
    |> builtins.filter (n: n != "default.nix" && !builtins.elem n excludes)
    |> builtins.map (n: ./. + "/${n}");
}
