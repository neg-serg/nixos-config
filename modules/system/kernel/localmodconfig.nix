{ lib, pkgs, ... }:

let
  # Build a minimal kernel using our localmodconfig-derived .config
  # configfile is a checked-in path (no IFD needed)
  minimalKernel = pkgs.linuxManualConfig {
    inherit (pkgs.linuxPackages.kernel) version src modDirVersion;
    configfile = ./localmodconfig.config;
    allowImportFromDerivation = false;
  };
in
{
  # Use mkOverride 40 to beat hardware.nix's lib.mkForce (priority 50)
  # This ensures our minimized kernel is used even when hosts/odin
  # forces LTS kernel via lib.mkForce
  boot.kernelPackages = lib.mkOverride 40 (pkgs.linuxKernel.packagesFor minimalKernel);
}
