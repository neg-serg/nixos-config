{ ... }:
{
  imports =
    let
      excludes = [
        "disabled-modules.nix" # imported directly by flake/nixos.nix (commonModules, outside domain filter)
        "vm" # imported explicitly below as ./vm/definitions.nix
      ];
    in
    (
      builtins.readDir ./.
      |> builtins.attrNames
      |> builtins.filter (n: n != "default.nix" && !builtins.elem n excludes)
      |> builtins.map (n: ./. + "/${n}")
    )
    ++ [ ./vm/definitions.nix ];
}
