{
  description = "Neg-Serg configuration";
  nixConfig = {
    extra-experimental-features = "pipe-operators";
  };
  inputs = {
    # Determinate Nix 3.23.3 (determinate + nix-src share the release tag on
    # purpose — the module installs the determinate-nixd binary that pairs with
    # the nix build, so bump both together). Bumped from 3.21.7: on that rev
    # packaging/everything.nix and src/perl/package.nix still used the deprecated
    # `stdenv.isLinux`/`stdenv.isDarwin` attributes, which every rebuild printed
    # as evaluation warnings; 3.23.3 uses hostPlatform and dropped the Perl
    # bindings. Re-lock with `just update` or:
    #   nix flake lock --update-input determinate --update-input nix-src
    determinate = {
      url = "github:DeterminateSystems/determinate/5f516660eb6faa93f5cb83ef493345967ca719ef";
      inputs.nix.follows = "nix-src";
      # Determinate's own nixpkgs pins flakehub nixpkgs-weekly, which is
      # unreachable from this host; follow the top-level nixpkgs input instead.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-src = {
      url = "github:DeterminateSystems/nix-src/74d688aa7b83ee1894ac1881eb3421b4c3fe3677";
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
    # The current rev is the published nixos-unstable channel release of
    # 2026-10-14 (Herdr 0.9.3): a channel release keeps the closure
    # substitutable from cache.nixos.org instead of building from source, and
    # Herdr >= 0.9.2 is what enables native agent-session restore.
    nixpkgs.url = "github:NixOS/nixpkgs/7fd4004d0511991fff3a0524856a9be09e28c5f0";

    # ROCm/PyTorch env is pinned to the previous rev (packages/torch-rocm):
    # the 2026-09 nixpkgs ships python3-torch 2.13.0, whose HIP build needs
    # aotriton 0.12b while rocmPackages still provides 0.11.1b → it fails in
    # aten/src/ATen/native/transformers/hip (aotriton_adapter.h 'cookie',
    # VarlenType::StridedVarlen, attn_options.deterministic). The older rev
    # has torch 2.12.0, which builds against aotriton 0.11.1b. Drop this input
    # (and use inputs.nixpkgs in packages/torch-rocm) once they line up.
    nixpkgs-torch.url = "github:NixOS/nixpkgs/9f160d09877b6203da7a04528b014469441e1bd9";
    nix-flatpak = {
      url = "github:gmodena/nix-flatpak";
    };
    raise = {
      url = "github:neg-serg/raise";
    };
    wl = {
      # Temporary: the layer-surface damage fix on top of main — a wallpaper that
      # swaps from outside (Vulkan WSI present without damage) must not leave the
      # compositor's cached copy of the surface behind panel popups. Switch back
      # to "github:neg-serg/wl" once the branch is merged into main.
      url = "git+ssh://git@github.com/neg-serg/wl?ref=fix/layer-backdrop-damage";
      flake = false;
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
      inputs.wl.follows = "wl";
      inputs.rsmetrx.follows = "rsmetrx";
    };
    # Vendored Renoise/Redux installers (licensed builds, >100 MB). They cannot
    # live in this repo — GitHub rejects files >100 MB — and moving them inside
    # the tree does not help: the flake source contains tracked files only,
    # while absolute paths are forbidden in pure evaluation. Keep them in
    # /home/neg/nixos-src/renoise on trantor; they arrive as a path input.
    renoise-src = {
      url = "path:/home/neg/nixos-src/renoise";
      flake = false;
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
    pleamar = {
      # Pinned 2026-10-16: v0.4.11 @ 57568fa, the rev of the local checkout
      # ~/src/pleamar. Update with:
      # nix flake lock --update-input pleamar
      url = "github:k4ditano/pleamar/57568fa7e9b2b432cc18f074f4fc7ec283bae952";
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
    # CachyOS-patched kernels (BORE/eevdf schedulers, zen4 CPU tunings) + ZFS
    # module. Deliberately NOT following nixpkgs: upstream warns that overriding
    # its nixpkgs input can mismatch patches and kernel versions.
    # Pinned rev (release branch, 2026-09-01) — same reason as multiverse above.
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/594956b9640690cf0079d03d6b3a6a8f380ceea3";
    # Waylandar — standalone Wayland calendar widget + dashboard (Quickshell + Python).
    # Local clone ~/src/waylandar is at the same rev; nixpkgs follows the top-level
    # pin so the build reuses the cached quickshell/python closure.
    waylandar = {
      url = "github:samjoshuadud/waylandar/b46d5c348f846ca489071f2d271312ea35c019b4";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # NERV-styled UEFI boot menu (GuillotineMelody/nervboot on Codeberg) — the
    # visible boot menu on trantor: firmware boots its NERV entry, it reads the
    # BLS entries systemd-boot writes and hands the pick back to systemd-boot.
    # Imported in hosts/trantor/default.nix; standalone build: `nix build .#nerv-boot`.
    nerv-boot = {
      url = "git+https://codeberg.org/GuillotineMelody/nervboot";
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
          mkSpecialArgs = nixosOut.mkSpecialArgs;
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
