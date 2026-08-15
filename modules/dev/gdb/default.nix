{
  lib,
  config,
  pkgs,
  ...
}:
let
  devEnabled = config.lib.neg.enabled "dev";
  packages = [
    pkgs.gdb # GNU debugger core with python pretty printers
  ];
in
{
  config = lib.mkIf devEnabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
