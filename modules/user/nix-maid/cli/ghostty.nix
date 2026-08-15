##
# Module: nix-maid/cli/ghostty
# Purpose: Ghostty terminal emulator configuration (ported from kitty feature parity).
# Ported from legacy Salt config (stuff/ghostty/config).
{ config, neg, ... }:

{
  config = neg.mkHomeFiles {
    ".config/ghostty/config".source = config.lib.neg.path "files/cli/ghostty/config";
  };
}
