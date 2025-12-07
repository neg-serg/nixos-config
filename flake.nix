{
  description = "Neg-Serg configuration";
  inputs = {
    # Pin hy3 to release compatible with Hyprland v0.52.x
    hy3 = {
      url = "git+https://github.com/outfoxxed/hy3?ref=hl0.52.0";
      inputs.hyprland.follows = "hyprland";
    };
    # Pin Hyprland to v0.52.x to align with the current desktop stack
    hyprland = {
      url = "git+https://github.com/hyprwm/Hyprland?ref=v0.52.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Keep selected Hyprland-related inputs in lockstep with the tracked Hyprland flake
    hyprland-protocols.follows = "hyprland/hyprland-protocols";
    # xdg-desktop-portal-hyprland is named 'xdph' inside the Hyprland flake inputs
    xdg-desktop-portal-hyprland.follows = "hyprland/xdph";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    iosevka-neg = {
      url = "git+ssh://git@github.com/neg-serg/iosevka-neg";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    iwmenu = {
      url = "github:e-tho/iwmenu";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-flatpak = {url = "github:gmodena/nix-flatpak";}; # unstable branch. Use github:gmodena/nix-flatpak/?ref=<tag> to pin releases.
    # Pin nixpkgs to nixos-unstable so we get Hydra cache hits
    nixpkgs = {url = "github:NixOS/nixpkgs/nixos-25.11";};
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyprland = {
      url = "github:hyprland-community/pyprland/e82637d73207abd634a96ea21fa937455374d131";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    raise = {
      url = "github:neg-serg/raise";
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
    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    yandex-browser = {
      url = "github:miuirussia/yandex-browser.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Make Cachix caches available to all `nix {build,develop,run}` commands
  # Note: nixConfig must stay a literal attrset (no imports/lets).
  nixConfig = {
    extra-substituters = [
      "https://0uptime.cachix.org"
      "https://0uptime.cachix.org"
      "https://cuda-maintainers.cachix.org"
      "https://devenv.cachix.org"
      "https://ezkea.cachix.org"
      "https://hercules-ci.cachix.org"
      "https://hyprland.cachix.org"
      "https://neg-serg.cachix.org"
      "https://nix-community.cachix.org"
      "https://nixpkgs-unfree.cachix.org"
      "https://nixpkgs-wayland.cachix.org"
      "https://numtide.cachix.org"
    ];
    extra-trusted-public-keys = [
      "0uptime.cachix.org-1:ctw8yknBLg9cZBdqss+5krAem0sHYdISkw/IFdRbYdE="
      "0uptime.cachix.org-1:ctw8yknBLg9cZBdqss+5krAem0sHYdISkw/IFdRbYdE="
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
      "hercules-ci.cachix.org-1:ZZeDl9Va+xe9j+KqdzoBZMFJHVQ42Uu/c/1/KMC5Lw0="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "neg-serg.cachix.org-1:MZ+xYOrDj1Uhq8GTJAg//KrS4fAPpnIvaWU/w3Qz/wo="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
      "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA"
      "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
    ];
  };
  outputs = inputs @ {
    self,
    nixpkgs,
    ...
  }:
    with {
      # Common lib
      inherit (nixpkgs) lib;
      flakeLib = import ./flake/lib.nix {inherit inputs nixpkgs;};
    }; let
      # Supported systems for generic flake outputs
      supportedSystems = ["x86_64-linux" "aarch64-linux"];
      # Linux system for NixOS configurations and docs evaluation
      linuxSystem = "x86_64-linux";

      hmDefaultSystem = linuxSystem;
      hmSystems = [hmDefaultSystem];
      caches = import ./nix/caches.nix;
      dropDefault = url: url != "https://cache.nixos.org/";
      dropDefaultKey = key: key != "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=";
      hmExtraSubstituters = builtins.filter dropDefault caches.substituters;
      hmExtraTrustedKeys = builtins.filter dropDefaultKey caches."trusted-public-keys";

      # Per-system outputs factory
      perSystem = import ./flake/per-system.nix {
        inherit self inputs nixpkgs flakeLib;
      };

      hmPerSystem = lib.genAttrs hmSystems (
        system: let
          pkgs = flakeLib.mkPkgs system;
          iosevkaNeg = flakeLib.mkIosevkaNeg system;
          devTools = import ./flake/home/devtools.nix {inherit lib pkgs;};
          inherit (devTools) devNixTools rustBaseTools rustExtraTools;
          customPkgs = flakeLib.mkCustomPkgs pkgs;
        in {
          inherit pkgs iosevkaNeg;
          devShells = import ./flake/home/devshells.nix {
            inherit pkgs rustBaseTools rustExtraTools devNixTools;
          };
          packages = {default = pkgs.zsh;} // customPkgs;
          checks = import ./flake/home/checks.nix {
            inherit pkgs self system;
          };
        }
      );
      hmHelpers = import ./flake/home/hm-helpers.nix {
        inherit lib self;
        stylixInput = inputs.stylix;
        sopsNixInput = inputs."sops-nix";
      };
      mkHMArgs = import ./flake/home/mkHMArgs.nix {
        inherit lib inputs;
        perSystem = hmPerSystem;
        yandexBrowserInput = inputs."yandex-browser";
        nur = inputs.nur;
        extraSubstituters = hmExtraSubstituters;
        extraTrustedKeys = hmExtraTrustedKeys;
        hmInputs =
          builtins.mapAttrs (_: input: input // {type = "derivation";}) {
          };
      };
    in {
      # Per-system outputs: packages, formatter, checks, devShells, apps
      packages = lib.genAttrs supportedSystems (s: (perSystem s).packages);
      formatter = lib.genAttrs supportedSystems (s: (perSystem s).formatter);
      checks = lib.genAttrs supportedSystems (s: (perSystem s).checks);
      devShells = lib.genAttrs supportedSystems (s: (perSystem s).devShells);
      apps = lib.genAttrs supportedSystems (s: (perSystem s).apps);

      # NixOS configurations (linuxSystem only)
      nixosConfigurations = import ./flake/nixos.nix {inherit inputs nixpkgs;};

      # Home Manager configurations (linuxSystem only)
      homeConfigurations = import ./flake/home-configurations.nix {
        inherit inputs lib mkHMArgs hmHelpers;
        pkgs = hmPerSystem.${linuxSystem}.pkgs;
        system = linuxSystem;
      };
    };
}
