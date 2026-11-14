{ mkBool, ... }:
{
  options.features.cli = {
    enable = mkBool "enable CLI tooling (fastfetch blizzard wrappers and helpers)" true;
    yazi.enable = mkBool "enable yazi terminal file manager" true;
  };
}
