{
  lib,
  perSystem,
  systems,
  homeManagerInput,
  mkHMArgs,
  hmBaseModules,
  self,
}: let
  docsLib = import ./features-docs.nix {inherit lib;};
  homeFeaturesPath = self + "/home/modules/features.nix";
in
  lib.genAttrs systems (
    s: let
      inherit (perSystem.${s}) pkgs;
      featureOptionsItems = docsLib.getFeatureOptionsItems homeFeaturesPath;
    in {
      features-options-md = pkgs.writeText "features-options.md" (docsLib.renderFeaturesOptionsMd featureOptionsItems);
      features-options-json = pkgs.writeText "features-options.json" (docsLib.renderFeaturesOptionsJson featureOptionsItems);
    }
  )
