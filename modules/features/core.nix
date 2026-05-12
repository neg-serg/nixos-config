{ lib, ... }:
with lib;
let
  presets = import ../features-data/unfree-presets.nix;
  mkBool = desc: default: (lib.mkEnableOption desc) // { inherit default; };
in
{
  options.features = {
    # Global package exclusions for curated lists in modules that adopt this filter.
    excludePkgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of package names (pname) to exclude from curated home.packages lists.";
    };

    profile = mkOption {
      type = types.enum [
        "full"
        "lite"
      ];
      default = "full";
      description = "Profile preset that adjusts feature defaults: full or lite.";
    };

    allowUnfree = {
      preset = mkOption {
        type = types.enum (builtins.attrNames presets);
        default = "desktop";
        description = "Preset allowlist for unfree packages.";
      };
      extra = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Extra unfree package names to allow (in addition to preset).";
      };
      allowed = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Final allowlist of unfree package names (overrides preset if explicitly set).";
      };
    };

    # Development-speed mode: aggressively trim heavy features/inputs for faster local iteration
    devSpeed.enable = mkBool "enable dev-speed mode (trim heavy features for faster eval)" false;
  };
}
