{ lib, mkBool, ... }:
with lib;
{
  options.features = {
    # Global package exclusions for curated lists in modules that adopt this filter.
    excludePkgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of package names (pname) to exclude from curated home.packages lists.";
    };

    # NOTE: `features.profile` (singular) removed — was dead code.
    # Use `features.profiles` (plural, list) for profile composition.

    # Development-speed mode: aggressively trim heavy features/inputs for faster local iteration
    devSpeed.enable = mkBool "enable dev-speed mode (trim heavy features for faster eval)" false;
  };
}
