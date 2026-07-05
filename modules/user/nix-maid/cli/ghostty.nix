##
# Module: nix-maid/cli/ghostty
# Purpose: Ghostty terminal emulator configuration (ported from kitty feature parity).
# Ported from legacy Salt config (stuff/ghostty/config).
{
  lib,
  neg,
  ...
}:
let
  n = neg;
in
{
  config = n.mkHomeFiles {
    ".config/ghostty/config".source = ../../../../files/cli/ghostty/config;
  };
}
