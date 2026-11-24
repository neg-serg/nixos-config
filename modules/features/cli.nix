{ mkBool, ... }:
{
  options.features.cli = {
    enable = mkBool "enable CLI tooling (fastfetch blizzard wrappers and helpers)" true;
    yazi.enable = mkBool "enable yazi terminal file manager" true;
    uutils.enable = mkBool "shadow GNU coreutils with uutils-coreutils on PATH (experiment)" false;
  };
}
