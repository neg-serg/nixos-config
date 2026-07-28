{ ... }:
{
  imports =
    let
      excludes = [
        "disabled-modules.nix" # dead code — not imported anywhere
        "vm"           # imported explicitly below as ./vm/definitions.nix
      ];
    in
      builtins.readDir ./.
      |> builtins.attrNames
      |> builtins.filter (n: n != "default.nix" && !builtins.elem n excludes)
      |> map (n: ./. + "/${n}")
      ++ [ ./vm/definitions.nix ];
}
