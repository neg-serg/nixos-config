{
  lib,
  perSystem,
  systems,
  homeManagerInput,
  mkHMArgs,
  hmBaseModules,
  boolEnv,
}: let
  docsLib = import ./features-docs.nix {inherit lib;};
in
  lib.genAttrs systems (
    s: let
      inherit (perSystem.${s}) pkgs;
      docsEnabled = boolEnv "HM_DOCS";
    in
      if docsEnabled
      then let
        featureOptionsItems = docsLib.getFeatureOptionsItems ../modules/features.nix;
      in {
        options-md = pkgs.writeText "OPTIONS.md" (
          let
            evalCfg = mods:
              homeManagerInput.lib.homeManagerConfiguration {
                inherit (perSystem.${s}) pkgs;
                extraSpecialArgs = mkHMArgs s;
                modules = mods;
              };
            hmFeaturesFor = profile:
              (evalCfg (hmBaseModules {inherit profile;})).config.features;
            fNeg = hmFeaturesFor null;
            fLite = hmFeaturesFor "lite";
            toFlat = set: prefix:
              lib.foldl' (
                acc: name: let
                  cur = lib.optionalString (prefix != "") (prefix + ".") + name;
                  v = set.${name};
                in
                  acc
                  // (
                    if builtins.isAttrs v
                    then toFlat v cur
                    else if builtins.isBool v
                    then {${cur} = v;}
                    else {}
                  )
              ) {} (builtins.attrNames set);
            flatNeg = toFlat fNeg "features";
            flatLite = toFlat fLite "features";
            deltas = docsLib.renderDeltasMd {inherit flatNeg flatLite;};
          in
            (builtins.readFile ../OPTIONS.md)
            + "\n\n"
            + deltas
        );
        features-options-md = pkgs.writeText "features-options.md" (docsLib.renderFeaturesOptionsMd featureOptionsItems);
        features-options-json = pkgs.writeText "features-options.json" (docsLib.renderFeaturesOptionsJson featureOptionsItems);
      }
      else {
        options-md = pkgs.writeText "OPTIONS.md" ''
          Docs generation is disabled.
          Set HM_DOCS=1 to enable heavy docs evaluation.
        '';
      }
  )
