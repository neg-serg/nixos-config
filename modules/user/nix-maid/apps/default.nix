{
  lib,
  ...
}:
let
  entries = builtins.readDir ./.;
in
{
  # dsh-tui-ru-assets/, dsh-osm/, dsh-widgets/ and dsh-web-en-assets/ are data
  # (patch scripts, plugin bundles, translation maps) consumed by their modules
  # — not modules themselves. (dsh-gui-tweaks/prompt/layout-slash now live in
  # the dsh-web-ui fork checkout, see their modules.)
  imports =
    builtins.attrNames entries
    |> builtins.filter (
      n:
      n != "default.nix"
      && n != "dsh-tui-ru-assets"
      && n != "dsh-osm"
      && n != "dsh-widgets"
      && n != "dsh-web-en-assets"
      && (entries.${n} == "directory" || lib.hasSuffix ".nix" n)
    )
    |> builtins.map (n: ./. + "/${n}");
}
