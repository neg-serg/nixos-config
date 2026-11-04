{
  config,
  inputs,
  self,
  ...
}:
{
  # packages and formatter still share one builder (flake/per-system.nix);
  # every other per-system output owns a part file of its own.
  perSystem =
    { system, pkgs, ... }:
    (import ../per-system.nix {
      inherit self inputs pkgs;
      inherit (inputs) nixpkgs;
      flakeLib = config.neg.lib;
    } system);
}
