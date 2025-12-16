{
  lib,
  config,
  ...
}: let
  devEnabled = config.features.dev.enable or false;
  packages = [
    # Keeping file for potential system-wide tools
  ];
in {
  config = lib.mkIf devEnabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
