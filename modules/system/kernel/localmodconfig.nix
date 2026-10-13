{
  lib,
  pkgs,
  neg,
  repoRoot,
  config,
  ...
}:

let
  # Pure resolver: this file reads the repo in a top-level `let`, where
  # config.lib.neg.* is not available yet (module args are forced while the
  # module is being collected) — see lib/README.md → By name, not by path.
  r = neg.rooted repoRoot;

  # 7.2.x (latest) instead of 6.18.x (default): the ZFS module nixpkgs ships
  # (zfs_2_4 = 2.4.4) officially supports 7.2, and cache-aware scheduling is
  # the reason for the bump. MT6639 Bluetooth needs no patches on >= 7.2:
  # btusb.c carries USB_DEVICE(0x13d3, 0x3588) and btmtk.c picks
  # (num_altsetting > 1) ? 1 : 0; both are in-tree. Kernels older than 7.2
  # (6.18.x LTS and below) are not supported on this host.
  baseKernel = pkgs.linuxPackages_latest.kernel;

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
  # Parsed .config for build.nix; named kernelConfig so the module-level
  # `config` argument stays available for feature lookups below.
  kernelConfig = readConfig (
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
    src = baseKernel.src;
    inherit configfile;
    config = kernelConfig;
    extraMakeFlags = [ "LOCALMODCONFIG_HASH=${configHash}" ];
    allowImportFromDerivation = false;
  };

  # Experimental kernel from torvalds/linux branch noref-filemap-read-with-llm:
  # v7.3-rc6 plus nine commits that read the page cache without taking folio
  # references and free retired folios only after an RCU grace period. Built
  # with the same reduced .config as the default kernel. The branch has no
  # GitHub mirror, so it is fetched from git.kernel.org; bump norefRev when
  # advancing, then re-check norefVersion against the Makefile and boot it.
  norefRev = "4c0f3697118eb3a708ea79175f7f07c43339bfab";
  norefVersion = "7.3.0-rc6"; # Makefile: VERSION=7 PATCHLEVEL=3 SUBLEVEL=0 EXTRAVERSION=-rc6
  norefSrc = builtins.fetchGit {
    url = "https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git";
    rev = norefRev;
    # linux.git is ~5 GB; shallow keeps the fetch to the pinned commit.
    shallow = true;
  };
  norefKernel = pkgs.linuxManualConfig {
    version = norefVersion;
    modDirVersion = norefVersion;
    inherit (baseKernel) features;
    src = norefSrc;
    inherit configfile;
    config = kernelConfig;
    extraMakeFlags = [ "LOCALMODCONFIG_HASH=${configHash}" ];
    allowImportFromDerivation = false;
  };
in
{
  # Use mkOverride 40 to beat hardware.nix's lib.mkForce (priority 50)
  # This ensures our minimized kernel is used even when hosts/trantor
  # forces LTS kernel via lib.mkForce
  boot.kernelPackages = lib.mkOverride 40 (
    let
      noref = config.features.system.norefKernel.enable;
      kernelPackages = pkgs.linuxKernel.packagesFor (if noref then norefKernel else minimalKernel);
    in
    if noref then
      kernelPackages.extend (
        _self: super: {
          # zfs_2_4 (2.4.4) declares support only through 7.2, so nixpkgs marks
          # the module broken on 7.3-rc6 and withholds --enable-linux-experimental.
          # Both are cleared here: the ZFS root on this host must stay mountable.
          # The four patches are the 7.3 API backports from OpenZFS master
          # (bvec_iter.bi_bvec_done -> bi_offset, cpu_feature_enabled,
          # iops->create without the flag arg, host fs for kernel threads);
          # zfs-2.4.5-staging does not carry them yet.
          zfs_2_4 = super.zfs_2_4.overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [
              (r.path "files/patches/zfs-7.3-bvec-bi-offset.patch")
              (r.path "files/patches/zfs-7.3-cpu-feature-enabled.patch")
              (r.path "files/patches/zfs-7.3-iops-create-no-flag.patch")
              (r.path "files/patches/zfs-7.3-kthread-host-fs.patch")
            ];
            configureFlags = (old.configureFlags or [ ]) ++ [ "--enable-linux-experimental" ];
            meta = (old.meta or { }) // {
              broken = false;
            };
          });
        }
      )
    else
      kernelPackages
  );
}
