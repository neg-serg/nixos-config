{
  lib,
  ...
}:
let
  entries = builtins.readDir ./.;
in
{
  # dsh-tui-ru-assets/, dsh-gui-tweaks-assets/, dsh-prompt-assets/,
  # dsh-layout-slash-assets/, dsh-osm/ and dsh-web-en-assets/ are data (patch
  # scripts, plugin bundles, translation maps) consumed by their modules — not
  # modules themselves.
  imports =
    builtins.attrNames entries
    |> builtins.filter (
      n:
      n != "default.nix"
      && n != "dsh-tui-ru-assets"
      && n != "dsh-gui-tweaks-assets"
      && n != "dsh-prompt-assets"
      && n != "dsh-layout-slash-assets"
      && n != "dsh-osm"
      && n != "dsh-web-en-assets"
      && (entries.${n} == "directory" || lib.hasSuffix ".nix" n)
    )
    |> builtins.map (n: ./. + "/${n}");
}
