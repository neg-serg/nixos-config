{ config, inputs, ... }:
{
  perSystem =
    { system, pkgs, ... }:
    {
      devShells =
        (import ../devshells.nix {
          inherit pkgs inputs;
          inherit (inputs) nixpkgs;
          flakeLib = config.neg.lib;
        } system).devShells;
    };
}
