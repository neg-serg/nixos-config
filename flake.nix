{
  description = "Neg-Serg configuration";

  inputs = {
    # === Core ===
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # === Hyprland ecosystem (requires follows) ===
    hyprland = {
      url = "git+https://github.com/hyprwm/Hyprland?ref=v0.52.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hy3 = {
      url = "git+https://github.com/outfoxxed/hy3?ref=hl0.52.0";
      inputs.hyprland.follows = "hyprland";
    };
    hyprland-protocols.follows = "hyprland/hyprland-protocols";
    xdg-desktop-portal-hyprland.follows = "hyprland/xdph";
    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # === Heavy deps (benefit from shared nixpkgs) ===
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nvf = {
      url = "github:NotAShelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nyx = {
      url = "github:chaotic-cx/nyx";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:Mic92/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    iosevka-neg = {
      url = "github:neg-serg/iosevka-neg";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rsmetrx = {
      url = "github:neg-serg/rsmetrx";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # === Independent tools (no follows needed) ===
    impurity.url = "git+file:///home/neg/src/impurity.nix";
    iwmenu.url = "github:e-tho/iwmenu";

    nix-flatpak.url = "github:gmodena/nix-flatpak";

    nix-maid.url = "github:viperML/nix-maid";

    pyprland = {
      url = "github:hyprland-community/pyprland/e82637d73207abd634a96ea21fa937455374d131";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    raise = {
      url = "github:neg-serg/raise";
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

    wrapper-manager.url = "github:viperML/wrapper-manager";

    yazi = {
      url = "github:sxyazi/yazi";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # === Special cases ===
  };

  nixConfig = {
    extra-substituters = [
      "https://0uptime.cachix.org"
      "https://cuda-maintainers.cachix.org"
      "https://devenv.cachix.org"
      "https://hercules-ci.cachix.org"
      "https://hyprland.cachix.org"
      "https://neg-serg.cachix.org"
      "https://nix-community.cachix.org"
      "https://nixpkgs-unfree.cachix.org"
      "https://numtide.cachix.org"
    ];
    extra-trusted-public-keys = [
      "0uptime.cachix.org-1:ctw8yknBLg9cZBdqss+5krAem0sHYdISkw/IFdRbYdE="
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "hercules-ci.cachix.org-1:ZZeDl9Va+xe9j+KqdzoBZMFJHVQ42Uu/c/1/KMC5Lw0="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "neg-serg.cachix.org-1:MZ+xYOrDj1Uhq8GTJAg//KrS4fAPpnIvaWU/w3Qz/wo="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
      "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
    ];
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    ...
  }: let
    inherit (nixpkgs) lib;
    flakeLib = import ./flake/lib.nix {
      inputs = inputs // {inherit self;};
      inherit nixpkgs;
    };
    supportedSystems = ["x86_64-linux"];
    perSystem = import ./flake/per-system.nix {inherit self inputs nixpkgs flakeLib;};
  in {
    packages = lib.genAttrs supportedSystems (s: (perSystem s).packages);
    formatter = lib.genAttrs supportedSystems (s: (perSystem s).formatter);
    checks = lib.genAttrs supportedSystems (s: (perSystem s).checks);
    devShells = lib.genAttrs supportedSystems (s: (perSystem s).devShells);
    apps = lib.genAttrs supportedSystems (s: (perSystem s).apps);
    nixosConfigurations = import ./flake/nixos.nix {inherit inputs nixpkgs self;};
  };
}
