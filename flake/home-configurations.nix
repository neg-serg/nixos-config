{
  inputs,
  mkHMArgs,
  hmHelpers,
  pkgs,
  system,
}: let
  inherit (inputs.home-manager.lib) homeManagerConfiguration;
in {
  neg = homeManagerConfiguration {
    inherit pkgs;
    modules = hmHelpers.hmBaseModules {
      profile = "full";
    };
    extraSpecialArgs = mkHMArgs system;
  };
}
