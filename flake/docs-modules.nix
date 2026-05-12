{
  pkgs,
  lib,
  self,
}:
let
  # Evaluate the modules to get the options
  eval = lib.evalModules {
    modules = [
      # Include the features module
      (self + "/modules/features")
      # Mock necessary config for evaluation
      (
        { lib, ... }:
        {
          config._module.check = false;
          # Mock mkBool helper used in features.nix
          config.lib.neg.mkBool = desc: default: (lib.mkEnableOption desc) // { inherit default; };
        }
      )
      # Mock assertions to avoid evaluation errors
      (
        { lib, ... }:
        {
          options.assertions = lib.mkOption {
            type = lib.types.anything;
            visible = false;
          };
        }
      )
    ];
  };

  # Use nixosOptionsDoc to generate the documentation
  optionsDoc = pkgs.nixosOptionsDoc {
    options = eval.options;
    documentType = "none"; # Don't generate a full manual, just the options
    transformOptions =
      opt:
      opt
      // {
        # Clean up declarations to remove store paths
        declarations = map (
          decl:
          if lib.hasPrefix (toString self) (toString decl) then
            let
              subpath = lib.removePrefix (toString self) (toString decl);
            in
            {
              url = "https://github.com/neg-serg/nixos/blob/master${subpath}";
              name = subpath;
            }
          else
            decl
        ) opt.declarations;
      };
  };
in
pkgs.runCommand "modules-docs" { } ''
  mkdir -p $out
  cp ${optionsDoc.optionsCommonMark} $out/modules.md
''
