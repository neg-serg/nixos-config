{ lib, pkgs, ... }:

let
  # CachyOS LTS kernel source (6.18.x, patched) — same major as the previous
  # stock kernel, so ZFS 2.4 + all out-of-tree modules keep building. The
  # zen4/ADIOS config tunings do not survive the minimal-config rebuild below
  # (linuxManualConfig uses this host's trimmed .config instead), but the newer
  # patched source does. Latest/bore variants track 7.x, which breaks ZFS.
  baseKernel = pkgs.cachyosKernels.linuxPackages-cachyos-lts.kernel;

  # Backported MediaTek MT6639 (MT7927) Bluetooth support: odin's adapter
  # (13d3:3588, ASUS ROG STRIX X870E-E) reports CHIPID=0x0000 and 6.18.y
  # otherwise drives it as MT7922, failing with "hci0: Opcode 0x0c03
  # failed: -16". Backport of upstream 28b7c5a6db74 (+ 81f971c6abec,
  # 59c3ee19ca88). Patch: files/patches/mt6639-btmtk-6.18.patch.
  kernelSrc = pkgs.applyPatches {
    name = "linux-${baseKernel.version}-mt6639";
    src = baseKernel.src;
    patches = [ ../../../files/patches/mt6639-btmtk-6.18.patch ];
  };

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
      modDirVersion
      features
      ;
    src = kernelSrc;
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
