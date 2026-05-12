##
# Module: system/net/nscd
# Purpose: nscd/unscd configuration.
# Key options: none.
# Dependencies: pkgs.unscd.
{ pkgs, ... }:
{
  services.nscd.enableNsncd = false; # try to fix buggy nscd
  services.nscd.package = pkgs.unscd; # Less buggy replacement for the glibc name service cache d...
}
