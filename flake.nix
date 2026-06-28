{
  description = "Neg-Serg configuration";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    hyprland-protocols.follows = "hyprland/hyprland-protocols";
    hyprland = {
      url = "git+https://github.com/hyprwm/Hyprland?ref=refs/tags/v0.55.4";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-guiutils.follows = "hyprland/hyprland-guiutils";

    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/0";
    raise = {
      url = "github:neg-serg/raise";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    wl = {
      url = "github:neg-serg/wl";
      flake = false;
    };
    xdg-desktop-portal-hyprland.follows = "hyprland/xdph";

    extra-container.url = "github:erikarvstedt/extra-container";
    iosevka-neg = {
      url = "github:neg-serg/iosevka-neg";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
    };
    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-maid.url = "github:viperML/nix-maid";
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nyx = {
      url = "github:chaotic-cx/nyx";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    quickshell = {
      url = "git+https://git.outfoxxed.me/quickshell/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rsmetrx = {
      url = "github:neg-serg/rsmetrx";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    tailray = {
      url = "github:NotAShelf/tailray";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    winapps = {
      url = "github:winapps-org/winapps";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fsread-nvim = {
      url = "github:neg-serg/fsread.nvim";
      flake = false;
    };
    wrapper-manager.url = "github:viperML/wrapper-manager";
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    extra-substituters = [ "https://install.determinate.systems" "https://cache.nixos.org" ];
    extra-trusted-public-keys = [ "install.determinate.systems:2/bvnFWPrR6uxEXpB7XqOSykYemH8e8WoMWvoLLXpF4=" "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
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
      perSystem =
        system:
        import ./flake/per-system.nix {
          inherit
            self
            inputs
            nixpkgs
            flakeLib
            ;
          pkgs = sharedPackages.${system};
        } system;
    in
    {
      packages = lib.genAttrs supportedSystems (s: (perSystem s).packages);
      formatter = lib.genAttrs supportedSystems (s: (perSystem s).formatter);
      checks = lib.genAttrs supportedSystems (s: (perSystem s).checks);
      devShells = lib.genAttrs supportedSystems (s: (perSystem s).devShells);
      apps = lib.genAttrs supportedSystems (s: (perSystem s).apps);
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
