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
      # agentPKCS11Whitelist = "/nix/store/*";
      # or specific URL if you're paranoid
      # but beware this can break if you don't have exactly matching opensc versions
      agentPKCS11Whitelist = "${pkgs.opensc}/lib/opensc-pkcs11.so"; # Set of libraries and utilities to access smart cards
    };
  };
}
