{ lib, pkgs, ... }:

let
  baseKernel = pkgs.linuxPackages.kernel;

  # Kernel config = generated base + deliberate manual overlay
  # (H-series notes from the Jul-2026 kernel audit), merged in pure Nix.
  # builtins.toFile returns a string, so build.nix's isPath-based auto-
  # detection of `config` would not run — pass the parsed config explicitly
  # (mirrors build.nix's readConfig: CONFIG_*=y|m → isModular/dev outputs).
  mergeConfigs =
    baseText: overlayText:
    let
      symName =
        line:
        let
          m = lib.match "(# )?CONFIG_([A-Za-z0-9_]+)(=.*| is not set)?" line;
        in
        if m == null then null else lib.elemAt m 1;
      baseLines = lib.splitString "\n" baseText;
      overlayLines = lib.splitString "\n" overlayText;
      overlaySyms = lib.filter (l: symName l != null) overlayLines;
      overlayMap = lib.listToAttrs (
        map (l: {
          name = symName l;
          value = l;
        }) overlaySyms
      );
      baseSymNames = lib.filter (n: n != null) (map symName baseLines);
      hasBaseSym = name: lib.elem name baseSymNames;
      # base lines with overlay values substituted in place (no duplicates),
      # then overlay-only symbols appended at the end.
      baseOut = lib.concatMap (
        l:
        let
          s = symName l;
        in
        if s == null then [ l ] else [ (overlayMap.${s} or l) ]
      ) baseLines;
      overlayOnly = lib.concatMap (
        l:
        let
          s = symName l;
        in
        if s == null || hasBaseSym s then [ ] else [ l ]
      ) overlayLines;
    in
    lib.concatStringsSep "\n" (baseOut ++ overlayOnly);

  configfile = builtins.toFile "kernel.config" (
    mergeConfigs (builtins.readFile ./base.config) (builtins.readFile ./overlay.config)
  );
  readConfig =
    text:
    let
      matchLine =
        line:
        let
          m = lib.match "(CONFIG_[^=]+)=([ym])" line;
        in
        if m == null then
          [ ]
        else
          [
            {
              name = lib.elemAt m 0;
              value = lib.elemAt m 1;
            }
          ];
    in
    lib.listToAttrs (lib.concatMap matchLine (lib.splitString "\n" text));
  config = readConfig (
    mergeConfigs (builtins.readFile ./base.config) (builtins.readFile ./overlay.config)
  );
  # Content tracking for rebuilds: include hash in extraMakeFlags
  # so derivation hash changes when .config content changes.
  configHash = builtins.hashFile "sha256" configfile;
  minimalKernel = pkgs.linuxManualConfig {
    inherit (baseKernel)
      version
      src
      modDirVersion
      features
      ;
    inherit configfile config;
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
