{
  lib,
  perSystem,
  systems,
  self,
}: let
  docsLib = import ./features-docs.nix {inherit lib;};
  homeFeaturesPath = self + "/home/modules/features.nix";
  systemFeaturesPath = self + "/modules/features.nix";
in
  lib.genAttrs systems (
    s: let
      inherit (perSystem.${s}) pkgs;
      homeFeatureItems = docsLib.getFeatureOptionsItems {module = homeFeaturesPath;};
      systemFeatureItems = docsLib.getFeatureOptionsItems {
        module = systemFeaturesPath;
        specialArgs = {inputs = {inherit self;};};
      };
      featureOptionsItems = docsLib.mergeFeatureItems {
        home = homeFeatureItems;
        system = systemFeatureItems;
      };
    in {
      features-options-md = pkgs.writeText "features-options.md" (docsLib.renderFeaturesOptionsMd featureOptionsItems);
      features-options-json = pkgs.writeText "features-options.json" (docsLib.renderFeaturesOptionsJson featureOptionsItems);
    }
  )
