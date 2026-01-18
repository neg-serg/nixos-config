{
  description = "Neg-Serg configuration";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11-small";

    hy3 = { url = "git+https://github.com/outfoxxed/hy3?ref=hl0.52.0"; inputs.hyprland.follows = "hyprland"; };
    hyprland-protocols.follows = "hyprland/hyprland-protocols";
    hyprland = { url = "git+https://github.com/hyprwm/Hyprland?ref=v0.52.1"; inputs.nixpkgs.follows = "nixpkgs"; };
    pyprland = { url = "github:hyprland-community/pyprland/e82637d73207abd634a96ea21fa937455374d131"; inputs.nixpkgs.follows = "nixpkgs"; };
    raise = { url = "github:neg-serg/raise"; inputs.nixpkgs.follows = "nixpkgs"; };
    xdg-desktop-portal-hyprland.follows = "hyprland/xdph";

    extra-container.url = "git+file:///home/neg/src/extra-container";
    iosevka-neg = { url = "github:neg-serg/iosevka-neg"; inputs.nixpkgs.follows = "nixpkgs"; };
    lanzaboote = { url = "github:nix-community/lanzaboote"; inputs.nixpkgs.follows = "nixpkgs"; inputs.rust-overlay.follows = "rust-overlay"; };
    microvm = { url = "github:microvm-nix/microvm.nix"; inputs.nixpkgs.follows = "nixpkgs"; };
    nix-flatpak.url = "github:gmodena/nix-flatpak";
    nix-maid.url = "github:viperML/nix-maid";
    nur = { url = "github:nix-community/NUR"; inputs.nixpkgs.follows = "nixpkgs"; };
    nyarch-assistant = { url = "github:neg-serg/nyarch-assistant"; inputs.nixpkgs.follows = "nixpkgs"; };
    nyx = { url = "github:chaotic-cx/nyx"; inputs.nixpkgs.follows = "nixpkgs"; inputs.rust-overlay.follows = "rust-overlay"; };
    pre-commit-hooks = { url = "github:cachix/git-hooks.nix"; inputs.nixpkgs.follows = "nixpkgs"; };
    quickshell = { url = "git+https://git.outfoxxed.me/quickshell/quickshell"; inputs.nixpkgs.follows = "nixpkgs"; };
    richcolors = { url = "github:neg-serg/richcolors"; inputs.nixpkgs.follows = "nixpkgs"; };
    rsmetrx = { url = "github:neg-serg/rsmetrx"; inputs.nixpkgs.follows = "nixpkgs"; };
    rtcqs = { url = "github:neg-serg/rtcqs"; inputs.nixpkgs.follows = "nixpkgs"; };
    rust-overlay = { url = "github:oxalica/rust-overlay"; inputs.nixpkgs.follows = "nixpkgs"; };
    sops-nix = { url = "github:Mic92/sops-nix"; inputs.nixpkgs.follows = "nixpkgs"; };
    tailray = { url = "github:NotAShelf/tailray"; inputs.nixpkgs.follows = "nixpkgs"; };
    tws = { url = "github:neg-serg/tws"; inputs.nixpkgs.follows = "nixpkgs"; };
    winapps = { url = "github:winapps-org/winapps"; inputs.nixpkgs.follows = "nixpkgs"; };
    fsread-nvim = { url = "github:neg-serg/fsread.nvim"; flake = false; };
    wrapper-manager.url = "github:viperML/wrapper-manager";
  };

  nixConfig = {
    # Only using official cache.nixos.org - no extra substituters
  };

  outputs =
    inputs@{self, nixpkgs, ...}:
    let
      inherit (nixpkgs) lib;
      flakeLib = import ./flake/lib.nix {
        inputs = inputs // { inherit self; };
        inherit nixpkgs;
      };
      supportedSystems = [ "x86_64-linux" ];
      sharedPackages = lib.genAttrs supportedSystems (system: flakeLib.mkPkgs system);
      perSystem =
        system:
        import ./flake/per-system.nix {
          inherit self inputs nixpkgs flakeLib;
          pkgs = sharedPackages.${system};
        } system;
    in {
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
