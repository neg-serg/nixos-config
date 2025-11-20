{
  lib,
  perSystem,
  systems,
  homeManagerInput,
  mkHMArgs,
  hmBaseModules,
}: let
  docsLib = import ./features-docs.nix {inherit lib;};
in
  lib.genAttrs systems (
    s: let
      inherit (perSystem.${s}) pkgs;
    in
      let
        featureOptionsItems = docsLib.getFeatureOptionsItems ../../home/modules/features.nix;
      in {
        features-options-md = pkgs.writeText "features-options.md" (docsLib.renderFeaturesOptionsMd featureOptionsItems);
        features-options-json = pkgs.writeText "features-options.json" (docsLib.renderFeaturesOptionsJson featureOptionsItems);
      }
  )
