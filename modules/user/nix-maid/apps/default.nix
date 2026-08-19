{
  lib,
  ...
}:
let
  entries = builtins.readDir ./.;
in
{
  # dsh-tui-ru-assets/, dsh-osm/, dsh-widgets/, dsh-web-en-assets/ and
  # dsh-liangshen-fork/ are data (patch scripts, plugin bundles, translation
  # maps, agent presets) consumed by their modules — not modules themselves.
  # (dsh-gui-tweaks/prompt/layout-slash now live in the dsh-web-ui fork
  # checkout, see their modules.)
  imports =
    builtins.attrNames entries
    |> builtins.filter (
      n:
      n != "default.nix"
      && n != "dsh-tui-ru-assets"
      && n != "dsh-osm"
      && n != "dsh-widgets"
      && n != "dsh-web-en-assets"
      && n != "dsh-liangshen-fork"
      && n != "dsh-mode"
      && n != "dsh-mobile"
      && n != "dsh-agent-usage-reminder"
      && n != "dsh-compaction-todo-preserver"
      && n != "dsh-rules-injector"
      && n != "dsh-category-skill-reminder"
      && n != "dsh-boulder"
      && n != "dsh-hashline"
      && (entries.${n} == "directory" || lib.hasSuffix ".nix" n)
    )
    |> builtins.map (n: ./. + "/${n}");
}
