{
  inputs,
  nixpkgs,
  ...
}:
let

  mkPkgs =
    system:
    import nixpkgs {
      inherit system;
      overlays = [
        ((import ../packages/overlay.nix) inputs)
      ];
      config = import ./pkgs-config.nix;
    };

  mkCustomPkgs = pkgs: import ../packages/flake/custom-packages.nix { inherit pkgs; };
  mkIosevkaNeg = system: inputs."iosevka-neg".packages.${system};
in
{
  inherit mkPkgs mkCustomPkgs mkIosevkaNeg;
}
