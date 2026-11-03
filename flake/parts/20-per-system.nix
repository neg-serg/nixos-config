{ config, ... }:
{
  # Existing per-system builders stay as they are; the dendritic layer only
  # decides where each flake output lives. Adding a new per-system output means
  # adding one line here (or a new part file).
  perSystem =
    { system, ... }:
    let
      mk = config.neg.mkPerSystem;
      perSystem = mk ../per-system.nix system;
    in
    {
      packages = perSystem.packages;
      formatter = perSystem.formatter;
      checks = perSystem.checks;
      apps = (mk ../apps.nix system).apps;
      devShells = (mk ../devshells.nix system).devShells;
    };
}
