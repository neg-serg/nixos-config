{
  description = "Neg-Serg configuration";
  nixConfig = {
    extra-experimental-features = "pipe-operators";
  };
  inputs = {
    # Dendritic pilot: `flake/devshells/` walks itself, so a new shell file needs
    # no list entry. `vic/import-tree` is the pattern's walker — deps-free, no
    # inputs of its own, MIT — pinned by flake.lock.
    import-tree.url = "github:vic/import-tree";
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
    # 2026-10-27 (Herdr 0.9.5): a channel release keeps the closure
    # substitutable from cache.nixos.org instead of building from source, and
    # Herdr >= 0.9.2 is what enables native agent-session restore.
    nixpkgs.url = "github:NixOS/nixpkgs/1c89083e451e891152365b799595cf7790a43325";

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
    # aurora: the MPD player's own repository — private, so the source stays off
    # the shelf while the package still builds the *committed* tree instead of
    # whatever sits in the working directory (~/src/aurora). It arrives over SSH,
    # which authenticates with the fetching user's GitHub key, so no token has to
    # be stored anywhere. Re-lock with
    # `nix flake lock --update-input aurora-src` after pushing to it.
    aurora-src = {
      url = "git+ssh://git@github.com/neg-serg/aurora";
      flake = false;
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
    pleamar = {
      # Upstream `main` (2026-11-01, runtime 0.7.7, scene language 0.9): the pin moved
      # from 0.4.31 after the shell was measured lagging, and every local patch in
      # `packages/overlays/gui.nix` was checked to apply in order on it. All scenes
      # still compile on the new language (`pleamar --check` over shells/*/*.plm).
      # Update with: edit the rev below to the new `main` commit, then
      #   nix flake lock --update-input pleamar
      url = "github:k4ditano/pleamar/bc710b193702d12f401cedea79541d94508861be";
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
    # Out-of-tree MT7927/MT6639 WiFi (mt76/mt7925e) + BT drivers for NixOS
    # (jetm dkms port). WiFi only: BT is handled by the in-tree 6.18 backport.
    # Pinned rev: API rate-limits block unpinned resolution; update with
    # `nix flake lock --update-input mt7927` once the limit clears.
    # REMOVED 2026-10-31: the 7.3 kernel carries mt7925e/MT7925 natively
    # (CONFIG_MT7925E), so the out-of-tree build is no longer needed — see
    # hosts/trantor/hardware.nix and modules/system/kernel/overlay.config (H22).
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
    # nix-cache-pin — rewrites a flake input to the newest revision whose
    # packages all have binary-cache hits (`nix run .#cache-pin-<pin>`, pins in
    # flake/cache-pin.nix). Fork: caniko/nix-cache-pin PR #20 (compromised-cache
    # ban) plus the redirect guard, which upstream does not ship yet. Follows the
    # top-level nixpkgs so the tool builds against the system pin.
    nix-cache-pin = {
      url = "github:neg-serg/nix-cache-pin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
