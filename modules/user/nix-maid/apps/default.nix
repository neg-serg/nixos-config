{ neg, ... }:
{
  # Data directories here are not modules (the dsh-* asset/preset bundles and
  # dsh-tui-ru-assets/); importDir skips directories without a default.nix.
  imports = neg.importDir {
    dir = ./.;
    includeDirs = true;
  };
}
