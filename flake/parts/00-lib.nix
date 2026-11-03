{
  inputs,
  self,
  lib,
  ...
}:
{
  options.neg.lib = lib.mkOption { type = lib.types.raw; };

  config.neg.lib = import ../lib.nix {
    inputs = inputs // {
      inherit self;
    };
    inherit (inputs) nixpkgs;
  };
}
