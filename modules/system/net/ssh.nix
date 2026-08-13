##
# Module: system/net/ssh
# Purpose: OpenSSH client basics (agent, PKCS#11).
# Key options: none.
# Dependencies: pkgs.openssh, pkgs.opensc.
{ pkgs, ... }:
{
  programs = {
    ssh = {
      package = pkgs.openssh; # Implementation of the SSH protocol
      startAgent = true;
      agentPKCS11Whitelist = "${pkgs.opensc}/lib/opensc-pkcs11.so"; # Set of libraries and utilities to access smart cards
    };
  };
}
