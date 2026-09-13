{ neg, ... }:
{
  programs.nano = {
    enable = false;
  };
  imports = neg.importDir {
    dir = ./.;
    includeDirs = true;
  };
}
