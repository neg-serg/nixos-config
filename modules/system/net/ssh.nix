##
# Module: system/net/ssh
# Purpose: OpenSSH client basics (agent, PKCS#11).
# Key options: none.
# Dependencies: pkgs.openssh, pkgs.tpm2-pkcs11 (security.tpmSudo).
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
      # PKCS#11 providers allowed via `ssh-add -s` (ssh-agent -P whitelist):
      # only the TPM2 store, and only when TPM-backed sudo is enabled.
      agentPKCS11Whitelist = lib.mkIf (config.lib.neg.enabled "security.tpmSudo") "${lib.getLib pkgs.tpm2-pkcs11}/lib/libtpm2_pkcs11.so";
    };
  };
}
