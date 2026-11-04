{
  config,
  inputs,
  self,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    {
      checks = import ../checks.nix {
        inherit self;
        inherit (inputs) nixpkgs;
        inherit (config.neg.nixosOut) mkTestHost mkSpecialArgs;
      } pkgs;
    };
}
