{ lib, neg, ... }:
{
  options.neg = {
    repoRoot = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos";
      description = "Path to the root of the configuration repository.";
    };

  };

  config = {
    _module.args.mkBool = desc: default: (lib.mkEnableOption desc) // { inherit default; };

    # Expose helpers under lib.neg for legacy or non-structural use.
    # We use the neg function from specialArgs.
    lib.neg = neg;
  };
}
