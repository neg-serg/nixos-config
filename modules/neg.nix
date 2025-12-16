{
  lib,
  pkgs,
  inputs,
  ...
}: {
  options.neg = {
    repoRoot = lib.mkOption {
      type = lib.types.path;
      default = inputs.self;
      description = "Root path of the flake repository.";
    };

    rofi.package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.rofi;
      description = "Primary Rofi package used by system-level wrappers.";
    };
  };
}
