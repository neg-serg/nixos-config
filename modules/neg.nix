{
  lib,
  pkgs,
  ...
}: {
  options.neg.rofi.package = lib.mkOption {
    type = lib.types.package;
    default = pkgs.rofi;
    description = "Primary Rofi package used by system-level wrappers.";
  };
}
