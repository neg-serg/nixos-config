{ ... }:
{
  imports = [
    ./minimize.nix
    ./localmodconfig.nix
    ./params.nix
    ./sysctl-mem-extras.nix
    ./sysctl-net-extras.nix
    ./sysctl-gaming.nix
    ./sysctl-writeback.nix
    ./sysctl.nix
  ];
}
