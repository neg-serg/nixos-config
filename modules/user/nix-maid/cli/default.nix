{ ... }:
{
  imports = [
    ./monitoring.nix
    ./yazi.nix
    ./search.nix
    ./utils.nix
  ];

  environment.systemPackages = [

  ];

  environment.variables.EZA_COLORS = "da=03:uu=01:gu=0:ur=0:uw=03:ux=04;38;5;24:gr=0:gx=01;38;5;24:tx=01;38;5;24;ur=00;ue=00:tr=00:tw=00:tx=00";
}
