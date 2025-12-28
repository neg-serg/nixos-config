{
  lib,
  pkgs,
  neg,
  impurity ? null,
  ...
}: {
  options.neg = {
    repoRoot = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos";
      description = "Path to the root of the configuration repository.";
    };
    rofi.package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.rofi;
      description = "The rofi package to use for the system.";
    };
  };

  config = {
    # Expose helpers under lib.neg for legacy or non-structural use.
    # We use the neg function from specialArgs.
    lib.neg = neg impurity;
  };
}
