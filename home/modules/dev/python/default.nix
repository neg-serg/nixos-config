{
  lib,
  config,
  ...
}:
lib.mkIf config.features.dev.enable {
  # Python runtimes now install via modules/dev/python/pkgs.nix at the system level.
}
