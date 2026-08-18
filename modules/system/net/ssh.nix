##
# Module: system/net/ssh
# Purpose: OpenSSH client basics (agent, PKCS#11).
# Key options: none.
# Dependencies: pkgs.openssh, pkgs.opensc.
{
  pkgs,
  config,
  lib,
  ...
}:
{
  programs = {
    ssh = {
      package = pkgs.openssh; # Implementation of the SSH protocol
      startAgent = true;
      # PKCS#11 providers allowed via `ssh-add -s` (ssh-agent -P whitelist).
      # tpm2-pkcs11 is appended only when TPM-backed sudo is enabled.
      agentPKCS11Whitelist =
        "${pkgs.opensc}/lib/opensc-pkcs11.so" # smart card support library
        + lib.optionalString (config.lib.neg.enabled "security.tpmSudo") ",${lib.getLib pkgs.tpm2-pkcs11}/lib/libtpm2_pkcs11.so";
    };
  };
}
