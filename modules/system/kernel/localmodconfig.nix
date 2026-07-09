{ lib, pkgs, ... }:

let
  baseKernel = pkgs.linuxPackages.kernel;
  configfile = ./localmodconfig.config;
  # Plain path preserves path type (builtins.isPath=true) needed by
  # build.nix for isModular detection → dev/modules outputs.
  # Content tracking for rebuilds: include hash in extraMakeFlags
  # so derivation hash changes when .config content changes.
  configHash = builtins.hashFile "sha256" configfile;
  minimalKernel = pkgs.linuxManualConfig {
    inherit (baseKernel) version src modDirVersion features;
    inherit configfile;
    extraMakeFlags = [ "LOCALMODCONFIG_HASH=${configHash}" ];
    allowImportFromDerivation = false;
  };
in
{
  # Use mkOverride 40 to beat hardware.nix's lib.mkForce (priority 50)
  # This ensures our minimized kernel is used even when hosts/odin
  # forces LTS kernel via lib.mkForce
  boot.kernelPackages = lib.mkOverride 40 (pkgs.linuxKernel.packagesFor minimalKernel);
}
