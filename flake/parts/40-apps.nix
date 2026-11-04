{ inputs, self, ... }:
{
  perSystem =
    { system, pkgs, ... }:
    {
      apps = (import ../apps.nix { inherit self inputs pkgs; } system).apps;
    };
}
