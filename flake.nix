{
  description = "Neg-Serg configuration";
  nixConfig = {
    extra-experimental-features = "pipe-operators";
  };
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nix-flatpak = {
      url = "github:gmodena/nix-flatpak";
    };
    hyprland = {
      url = "github:hyprwm/Hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hy3 = {
      url = "github:outfoxxed/hy3";
    };
    raise = {
      url = "github:neg-serg/raise";
    };
    wl = {
      url = "github:neg-serg/wl";
    };
    xdg-desktop-portal-hyprland.follows = "hyprland/xdph";

    iosevka-neg = {
      url = "github:neg-serg/iosevka-neg";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    neg-pkgs = {
      url = "github:neg-serg/nixos-pkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-maid.url = "github:viperML/nix-maid";
    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
    winapps = {
      url = "github:winapps-org/winapps";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    steam-config-nix = {
      url = "github:unazikx/steam-config-nix/feat/winetricks";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    herdr = {
      url = "github:ogulcancelik/herdr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sqlit = {
      url = "github:Maxteabag/sqlit";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    caelestia-shell = {
      url = "github:caelestia-dots/shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    talktype = {
      url = "github:lmacan1/talktype";
    };
    extra-container.url = "git+https://github.com/erikarvstedt/extra-container.git";
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

      # Dendritic per-system output: each output imports from its own file.
      # mkPerSystem is a thin closure-builder — each invocation creates an
      # independent eval unit for nix-eval-jobs parallelism.
      mkPerSystem =
        path: system:
        import path {
          inherit self inputs nixpkgs flakeLib;
          pkgs = sharedPackages.${system};
        } system;
    in
    {
      packages = lib.genAttrs supportedSystems (s: (mkPerSystem ./flake/per-system.nix s).packages);
      formatter = lib.genAttrs supportedSystems (s: (mkPerSystem ./flake/per-system.nix s).formatter);
      checks = lib.genAttrs supportedSystems (s: (mkPerSystem ./flake/per-system.nix s).checks);
      devShells = lib.genAttrs supportedSystems (s: (mkPerSystem ./flake/devshells.nix s).devShells);
      apps = lib.genAttrs supportedSystems (s: (mkPerSystem ./flake/apps.nix s).apps);
      nixosConfigurations = import ./flake/nixos.nix {
        inherit inputs nixpkgs self;
        pkgs = sharedPackages.x86_64-linux;
        filteredSource = lib.cleanSourceWith {
          filter = name: _type: !(lib.hasSuffix ".md" (builtins.baseNameOf name));
          src = lib.cleanSource ./.;
        };
      };
    };
}
