{ neg, ... }:
{
  # sing-box-tun-*.sh are data files — excluded by the .nix suffix filter
  imports = neg.importDir { dir = ./.; };
}
