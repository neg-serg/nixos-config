{
  config,
  lib,
  pkgs,
  ...
}:
{
  # throne — installed by modules/system/net/vpn/pkgs.nix (behind the same feature flag)
  environment.systemPackages = [ ];
}
