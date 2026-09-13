{ neg, ... }:
{
  # scripts/ is a data directory (no default.nix) — importDir skips it.
  imports = neg.importDir {
    dir = ./.;
    includeDirs = true;
  };
}
