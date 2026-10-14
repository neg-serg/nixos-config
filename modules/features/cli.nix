{ mkBool, ... }:
{
  options.features.cli = {
    enable = mkBool "enable CLI tooling (fastfetch blizzard wrappers and helpers)" true;
    broot.enable = mkBool "enable broot file manager and shell integration" false;
    yazi.enable = mkBool "enable yazi terminal file manager" true;
    fix.enable = mkBool "install fix, the fast Nix evaluator (patched master; eval/build helper)" false;
  };
}
