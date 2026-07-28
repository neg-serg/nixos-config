{ ... }:
{
  imports =
    let
      excludes = [
        "caches.data.nix" # data file, not a module
        "packages-overlay.nix" # removed — overlay already applied via flake/lib.nix mkPkgs
      ];
    in
      builtins.readDir ./.
      |> builtins.attrNames
      |> builtins.filter (n: n != "default.nix" && n != "README.md" && !builtins.elem n excludes)
      |> map (n: ./. + "/${n}");
}
