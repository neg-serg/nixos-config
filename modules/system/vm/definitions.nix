##
# Module: system/vm/definitions
# Purpose: Expose legacy libvirt domain XML definitions for optional use.
# Ported from legacy Salt config (gentoo.xml, nixos.xml, win11.xml).
# These are reference definitions — not automatically deployed.
{
  lib,
  ...
}:
let
  vmDefs = {
    gentoo = ./vm/definitions/gentoo.xml;
    nixos = ./vm/definitions/nixos.xml;
    win11 = ./vm/definitions/win11.xml;
  };
in
{
  options.system.vmDefinitions = lib.mkOption {
    type = lib.types.attrsOf lib.types.path;
    default = vmDefs;
    readOnly = true;
    description = "Legacy libvirt domain XML definitions (Gentoo, NixOS, Windows 11).";
  };
}
