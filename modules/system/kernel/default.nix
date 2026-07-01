{ ... }:
{
  imports = [
    ./params.nix
    ./sysctl-mem-extras.nix
    ./sysctl-net-extras.nix
    ./sysctl-writeback.nix
    ./sysctl.nix
  ];
}
