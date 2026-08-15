{
  lib,
  config,
  ...
}:
let
  devEnabled = config.lib.neg.enabled "dev";
  packages = [
    # Keeping file for potential system-wide tools
  ];
in
{
  config = lib.mkIf devEnabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
