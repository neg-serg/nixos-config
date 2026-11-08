{ inputs, ... }:
{
  perSystem =
    { system, pkgs, ... }:
    {
      devShells =
        (import ../devshells.nix {
          inherit pkgs inputs;
          inherit (inputs) nixpkgs;
        } system).devShells;
    };
}
