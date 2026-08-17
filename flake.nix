{
  description = "Neg-Serg configuration";
  nixConfig = {
    extra-experimental-features = "pipe-operators";
  };
  inputs = {
    determinate = {
      url = "github:DeterminateSystems/determinate/73b3bdb962a070aa088ac310e606ff760bcc0cf7";
      inputs.nix.follows = "nix-src";
    };
    nix-src = {
      url = "github:DeterminateSystems/nix-src/b1123363e07a216333222d483cfe8e682b95d7c1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # NB: the declared branch is nixos-26.05 (stable, deliberate — commit
    # e16f4269 reverted the nixpkgs-weekly experiment). If flake.lock drifts
    # (e.g. pins a weekly tarball), re-align with:
    #   nix flake lock --update-input nixpkgs
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
    # Private personal wiki (notes) — hosts the TidalCycles live-coding
    # "journey" (BootTidal.hs helpers, demo/scratch scenes, docs). Kept out of
    # the public nixos-pkgs repo on purpose. Fetched over SSH: GitHub API
    # returns 404 for this private repo's git-data endpoints (rate-limited IP),
    # while git+ssh works with the host key.
    personal-wiki = {
      url = "git+ssh://git@github.com/neg-serg/personal-wiki";
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
    neg-pkgs = {
      url = "github:neg-serg/nixos-pkgs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.talktype.follows = "talktype";
      inputs.wl.follows = "wl";
      inputs.rsmetrx.follows = "rsmetrx";
    };
    nix-maid.url = "github:viperML/nix-maid";
    hyprscratch = {
      url = "github:neg-serg/hyprscratch";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    quickshell = {
      url = "github:quickshell-mirror/quickshell";
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
