{
  description = "Neg-Serg configuration";
  nixConfig = {
    extra-experimental-features = "pipe-operators";
  };
  inputs = {
    determinate = {
      url = "github:DeterminateSystems/determinate/73b3bdb962a070aa088ac310e606ff760bcc0cf7";
      inputs.nix.follows = "nix-src";
      # Determinate's own nixpkgs pins flakehub nixpkgs-weekly, which is
      # unreachable from this host; follow the top-level nixpkgs input instead.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-src = {
      url = "github:DeterminateSystems/nix-src/b1123363e07a216333222d483cfe8e682b95d7c1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Moved to nixos-unstable (2026-08) for newer Hyprland/color-mgmt
    # (ICC + HDR). Deliberate, even though it re-locks nixpkgs: the pin from
    # nixos-26.05 (commit e16f4269, which reverted the weekly experiment) had
    # a stable Hyprland 0.55.4; unstable tracks 0.56+ with HDR/color-management
    # and keeps the compositor ecosystem in sync. Re-align drift with:
    #   nix flake lock --update-input nixpkgs
    #
    # Pinned to a concrete unstable HEAD rev because nix (in this repo/state)
    # refuses to re-resolve the floating `nixos-unstable` ref from the lock's
    # stale `nixos-25.11`/`nixos-26.05` originals (nix flake update/lock/
    # --recreate-lock-file all leave it at the old rev). Bump this rev with
    # `nix flake lock --update-input nixpkgs` once the ref resolution settles.
    # Pinned to an OLDER well-cached nixos-unstable rev (2026-08-12, Hyprland
    # 0.56.2) instead of the raw branch tip. The fresh tip (2c423e03, 08-22)
    # is not yet a published channel release, so many packages aren't in
    # cache.nixos.org and must build from source (flaky). This rev is a
    # published channel release → packages substitute from cache. Later,
    # bump with `nix flake lock --update-input nixpkgs`.
    nixpkgs.url = "github:NixOS/nixpkgs/9f160d09877b6203da7a04528b014469441e1bd9";
    nix-flatpak = {
      url = "github:gmodena/nix-flatpak";
    };
    hy3 = {
      url = "github:outfoxxed/hy3";
    };
    raise = {
      url = "github:neg-serg/raise";
    };
    wl = {
      url = "github:neg-serg/wl";
      flake = false;
    };
    # xdph used to follow the (now removed) hyprland input; pinned here to the
    # same rev the hyprland flake carried, so the portal version is unchanged.
    xdg-desktop-portal-hyprland = {
      url = "github:hyprwm/xdg-desktop-portal-hyprland/08d99f727944dd15e4740090305e31c5fb92a50a";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    iosevka-neg = {
      url = "github:neg-serg/iosevka-neg";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # lusty: own repo on github (source of truth).
    # Re-lock after pushes: nix flake lock --update-input lusty (via proxy).
    lusty = {
      url = "github:neg-serg/lusty";
    };
    neg-pkgs = {
      url = "github:neg-serg/nixos-pkgs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.talktype.follows = "talktype";
      inputs.wl.follows = "wl";
      inputs.rsmetrx.follows = "rsmetrx";
    };
    nix-maid.url = "git+https://codeberg.org/viperML/nix-maid";
    hyprscratch = {
      url = "github:neg-serg/hyprscratch";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    quickshell = {
      # Pinned 2026-09-03: master @ 2d3b3e9 (0.3.1 + post-0.3.1 fixes:
      # session-lock reentrancy guard, tray /NO_DBUSMENU, pam free fix,
      # scriptmodel compare, launch QCoreApplication ordering).
      # Known residual issue: still crashes on output-set transitions
      # (QSG teardown, ~/.cache/quickshell/crashes). Update with:
      # nix flake lock --update-input quickshell
      url = "github:quickshell-mirror/quickshell/2d3b3e9c70ef380dff751b61d334dc88df016c29";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rsmetrx = {
      url = "github:neg-serg/rsmetrx";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    tailray = {
      url = "github:NotAShelf/tailray";
    };
    steam-config-nix = {
      url = "github:unazikx/steam-config-nix/feat/winetricks";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    talktype = {
      url = "github:lmacan1/talktype";
      flake = false;
    };
    extra-container.url = "git+https://github.com/erikarvstedt/extra-container.git";
    colibri = {
      url = "github:JustVugg/colibri";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Out-of-tree MT7927/MT6639 WiFi (mt76/mt7925e) + BT drivers for NixOS
    # (jetm dkms port). WiFi only: BT is handled by the in-tree 6.18 backport.
    # Pinned rev: API rate-limits block unpinned resolution; update with
    # `nix flake lock --update-input mt7927` once the limit clears.
    mt7927 = {
      url = "github:cmspam/mt7927-nixos/2b6cd295d7c520f79bb490cdfe70fe8311de0c0e";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Pin any top-level nixpkgs attribute (pkgs.*) to an exact version from a
    # single flake input (no juggling multiple nixpkgs pins). Enabled via
    # modules/system/multiverse.nix; add pins there.
    # Pinned rev (main, 2026-09-01): unpinned resolution is blocked on this host
    # (api.github.com unreachable); update via nix flake lock --update-input multiverse.
    multiverse.url = "github:fzakaria/nixpkgs-multiverse/4e42650d06172b925d85b134fb924ae6d109cf60";
    # Nix library for wrapping executables via the module system (by Lassulus,
    # nh maintainer). Use as inputs.wrappers.lib.wrapPackage / .wrapperModules.
    wrappers = {
      url = "github:lassulus/wrappers/b870d84b4fbe38a5a1e38cd2dae8503805bec900";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # CachyOS-patched kernels (BORE/eevdf schedulers, zen4 CPU tunings) + ZFS
    # module. Deliberately NOT following nixpkgs: upstream warns that overriding
    # its nixpkgs input can mismatch patches and kernel versions.
    # Pinned rev (release branch, 2026-09-01) — same reason as multiverse above.
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/594956b9640690cf0079d03d6b3a6a8f380ceea3";
    # Declarative Agent Skills management (SKILL.md discovery/selection/bundling,
    # flake-pinned sources). Library via inputs.agent-skills.lib.agent-skills;
    # home-manager module not wired (this repo uses nix-maid, not home-manager).
    agent-skills = {
      url = "github:Kyure-A/agent-skills-nix/1594ba479be81a7cb6dd19faabefcb1ed5b3f964";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Waylandar — standalone Wayland calendar widget + dashboard (Quickshell + Python).
    # Local clone ~/src/waylandar is at the same rev; nixpkgs follows the top-level
    # pin so the build reuses the cached quickshell/python closure.
    waylandar = {
      url = "github:samjoshuadud/waylandar/b46d5c348f846ca489071f2d271312ea35c019b4";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ self, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
      flakeLib = import ./flake/lib.nix {
        inputs = inputs // {
          inherit self;
        };
        inherit nixpkgs;
      };
      supportedSystems = [ "x86_64-linux" ];
      sharedPackages = lib.genAttrs supportedSystems (system: flakeLib.mkPkgs system);

      # NixOS configuration builder: `nixosOut.configurations` is the pure
      # machine set (flake-schemas), `nixosOut.mkTestHost` serves flake/checks.nix.
      nixosOut = import ./flake/nixos.nix {
        inherit inputs nixpkgs self;
        pkgs = sharedPackages.x86_64-linux;
        filteredSource = lib.cleanSourceWith {
          filter = name: _type: !(lib.hasSuffix ".md" (builtins.baseNameOf name));
          src = lib.cleanSource ./.;
        };
      };

      # Dendritic per-system output: each output imports from its own file.
      # mkPerSystem is a thin closure-builder — each invocation creates an
      # independent eval unit for nix-eval-jobs parallelism.
      mkPerSystem =
        path: system:
        import path {
          inherit
            self
            inputs
            nixpkgs
            flakeLib
            ;
          mkTestHost = nixosOut.mkTestHost;
          pkgs = sharedPackages.${system};
        } system;
    in
    {
      packages = lib.genAttrs supportedSystems (s: (mkPerSystem ./flake/per-system.nix s).packages);
      formatter = lib.genAttrs supportedSystems (s: (mkPerSystem ./flake/per-system.nix s).formatter);
      checks = lib.genAttrs supportedSystems (s: (mkPerSystem ./flake/per-system.nix s).checks);
      devShells = lib.genAttrs supportedSystems (s: (mkPerSystem ./flake/devshells.nix s).devShells);
      apps = lib.genAttrs supportedSystems (s: (mkPerSystem ./flake/apps.nix s).apps);
      nixosConfigurations = nixosOut.configurations;
    };
}
