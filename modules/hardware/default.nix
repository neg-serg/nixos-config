# Hardware module aggregator
# Config and options moved to ./config.nix for flat-import compatibility
{ neg, ... }:
{
  imports = neg.importDir {
    dir = ./.;
    includeDirs = true;
  };
}
