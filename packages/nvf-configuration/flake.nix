{
  description = "Standalone NVF Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nvf.url = "github:NotAShelf/nvf";
    nvf.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nvf }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system}.extend (final: prev: {
        fsread-nvim = final.callPackage ./pkgs/fsread-nvim/default.nix { };
      });
      config = import ./config.nix { inherit pkgs; nvimConfPath = ./files/nvim; };
      customNeovim = nvf.lib.neovimConfiguration {
        inherit pkgs;
        modules = [ config ];
      };
    in {
      packages.${system}.default = customNeovim.neovim;

      homeManagerModules.default = { pkgs, ... }: {
        programs.nvf.settings = import ./config.nix {
          inherit pkgs;
          nvimConfPath = ./files/nvim;
        };
      };

      lib.mkConfig = args: import ./config.nix (args // { nvimConfPath = ./files/nvim; });
    };
}
