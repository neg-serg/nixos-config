##
# Module: nix-maid/cli/ghostty
# Purpose: Ghostty terminal emulator configuration (ported from kitty feature parity).
# Ported from legacy Salt config (stuff/ghostty/config).
#
# NOTE: kept intentionally as a migration reference — the ghostty package is NOT
# installed (kitty is the terminal). Also unusable with the Russian layout until
# a version with W3C key-code bindings (ghostty-org/ghostty#3513/#3584/#7320);
# see docs/howto/hotkeys-ru-layout.ru.md.
{ config, neg, ... }:

{
  config = neg.mkHomeFiles {
    ".config/ghostty/config".source = config.lib.neg.path "files/cli/ghostty/config";
  };
}
