##
# Module: security/tpm-sudo
# Purpose: Passwordless sudo with no manual actions, protected by the TPM.
#   A non-exportable SSH key stored in the TPM via tpm2-pkcs11 (empty PIN →
#   no interaction) is loaded into ssh-agent at login; `sudo` then
#   authenticates against that agent through pam_ssh_agent_auth instead of
#   asking for a password. The private key never leaves the TPM.
# Gate: features.security.tpmSudo.enable (default false). Enable fTPM in
#   UEFI/BIOS BEFORE flipping this on, otherwise boot stalls on the tpmrm
#   device wait. Full setup: docs/howto/tpm-sudo.ru.md.
# Dependencies: security.tpm2 (tpm2-tools/tpm2-pkcs11), pam_ssh_agent_auth,
#   openssh (ssh-agent + ssh-add).
{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf (config.lib.neg.enabled "security.tpmSudo") {
    # TPM2 stack + tpm2-pkcs11 store. The default udev rule hands /dev/tpmrm0
    # to root:tss; the main user is already in `tss` (modules/system/users.nix).
    security.tpm2 = {
      enable = true;
      pkcs11.enable = true;
      tctiEnvironment.enable = true; # TPM2TOOLS_TCTI / TPM2_PKCS11_TCTI → device:/dev/tpmrm0
    };

    # sudo via the SSH agent. Enabling sshAgentAuth also injects
    # `Defaults env_keep+=SSH_AUTH_SOCK` into sudoers (nixpkgs).
    security.pam.sshAgentAuth = {
      enable = true;
      # Root-owned, keyed by the INVOKING user (%u → neg). Never point at a
      # user-writeable path (nixpkgs#31611). Put the TPM key's public part in
      # /etc/ssh/authorized_keys.d/neg — see docs/howto/tpm-sudo.ru.md.
      authorizedKeysFiles = [ "/etc/ssh/authorized_keys.d/%u" ];
    };
    security.pam.services.sudo.sshAgentAuth = true;

    # Auto-load the TPM2 key into ssh-agent at login so `sudo` needs no
    # interaction. The agent is started by programs.ssh.startAgent; its socket
    # lives at %t/ssh-agent (XDG_RUNTIME_DIR).
    systemd.user.services.tpm2-ssh-add = {
      description = "Load the TPM2-backed SSH key into ssh-agent";
      wantedBy = [ "default.target" ];
      after = [ "ssh-agent.service" ];
      requires = [ "ssh-agent.service" ];
      serviceConfig = {
        Type = "oneshot";
        Environment = "SSH_AUTH_SOCK=%t/ssh-agent";
        ExecStart = "${pkgs.openssh}/bin/ssh-add -s ${lib.getLib pkgs.tpm2-pkcs11}/lib/libtpm2_pkcs11.so";
      };
    };
  };
}
