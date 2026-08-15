{
  lib,
  ...
}:
let
  entries = builtins.readDir ./.;
in
{
  # dsh-tui-ru/ is data (i18n.json / patch.mjs) consumed by dsh-tui-ru.nix
  imports =
    builtins.attrNames entries
    |> builtins.filter (n: n != "default.nix" && n != "dsh-tui-ru" && (entries.${n} == "directory" || lib.hasSuffix ".nix" n))
    |> builtins.map (n: ./. + "/${n}");
}
