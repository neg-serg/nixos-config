{
  pkgs,
  lib,
  mkShell,
  import-tree,
  ...
}:
let
  # Dendritic pilot: the shells are the files of this directory, walked by
  # import-tree instead of a hand-kept name list — a new `foo.nix` here becomes
  # the `foo` shell with no second edit. `default.nix` is this aggregator, and
  # importing it would recurse; `base.nix` backs the `default` shell, every
  # other file maps to a shell of the same name.
  files = (import-tree.filter (p: baseNameOf (toString p) != "default.nix")).leaves ./.;
  nameOf =
    p:
    let
      name = baseNameOf (toString p);
    in
    if name == "base.nix" then "default" else lib.removeSuffix ".nix" name;
in
builtins.listToAttrs (
  map (p: {
    name = nameOf p;
    value = mkShell (import p { inherit pkgs lib; });
  }) files
)
