{ lib, mkBool, ... }:
with lib;
{
  options.features = {
    # NOTE: `features.profile` (singular) removed — was dead code.
    # Use `features.profiles` (plural, list) for profile composition.

    # Development-speed mode: aggressively trim heavy features/inputs for faster local iteration
    devSpeed.enable = mkBool "enable dev-speed mode (trim heavy features for faster eval)" false;
  };
}
