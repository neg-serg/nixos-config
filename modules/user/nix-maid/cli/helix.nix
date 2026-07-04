##
# Module: nix-maid/cli/helix
# Purpose: Helix editor LSP configuration (17 language servers).
# Ported from legacy Salt config (stuff/helix/languages.toml).
{
  lib,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
in
{
  config = n.mkHomeFiles {
    ".config/helix/languages.toml".source = ../../../../files/cli/helix/languages.toml;
  };
}
