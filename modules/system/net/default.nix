{ neg, ... }:
{
  # Flat modules + module subdirectories (rkn, vpn, zapret2, net-health)
  imports = neg.importDir {
    dir = ./.;
    includeDirs = true;
  };
}
