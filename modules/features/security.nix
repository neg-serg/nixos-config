{ mkBool, ... }: {
  options.features.security = {
    # TPM-backed passwordless sudo: a non-exportable SSH key in the TPM
    # (tpm2-pkcs11, empty PIN) + pam_ssh_agent_auth for `sudo`. Flip on only
    # AFTER enabling fTPM in UEFI/BIOS — otherwise boot stalls on the tpmrm
    # device wait. See modules/security/tpm-sudo.nix and docs/howto/tpm-sudo.ru.md.
    tpmSudo.enable = mkBool "TPM-backed passwordless sudo (tpm2-pkcs11 + pam_ssh_agent_auth)" false;
  };
}
