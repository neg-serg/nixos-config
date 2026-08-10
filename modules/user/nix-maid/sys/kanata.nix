##
# Module: nix-maid/sys/kanata
# Purpose: Kanata keyboard remapper — ported from legacy Salt config.
# Requires uinput kernel module (enabled in hardware/uinput.nix).
{
  lib,
  config,
  neg,
  ...
}:
let
  cfg = config.features.input.kanata or { };
in
lib.mkIf (cfg.enable or false) {
  config = neg.mkHomeFiles {
    ".config/kanata/kanata.kbd".source = ../../../../files/cli/kanata/kanata.kbd;
  };

}
