{ neg, ... }:
{
  imports = neg.importDir {
    dir = ./.;
    includeDirs = true;
  };
}
