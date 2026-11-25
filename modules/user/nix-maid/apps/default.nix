{ neg, ... }:
{
  # Data directories here are not modules: importDir skips directories without a
  # default.nix, and the dsh profile data that used to need an explicit
  # exclusion lives in `github:neg-serg/dsh-app` now.
  imports = neg.importDir {
    dir = ./.;
    includeDirs = true;
  };
}
