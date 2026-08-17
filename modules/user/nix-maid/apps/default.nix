{
  lib,
  ...
}:
let
  entries = builtins.readDir ./.;
in
{
  # dsh-tui-ru-assets/ and dsh-gui-tweaks-assets/ are data (patch scripts,
  # plugin bundles) consumed by their modules — not modules themselves.
  imports =
    builtins.attrNames entries
    |> builtins.filter (
      n:
      n != "default.nix"
      && n != "dsh-tui-ru-assets"
      && n != "dsh-gui-tweaks-assets"
      && (entries.${n} == "directory" || lib.hasSuffix ".nix" n)
    )
    |> builtins.map (n: ./. + "/${n}");
}
