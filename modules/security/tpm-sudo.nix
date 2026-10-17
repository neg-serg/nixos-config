#
# TPM-sudo — passwordless sudo via TPM (no manual steps)
# (moved out of the docs tree; keep it in sync with the code it describes)
#
#
# How to get `sudo` without typing a password yet with protection: the private SSH key lives **inside
# the TPM** (non-exportable) and signs requests without a PIN; `sudo` authenticates through the
# ssh-agent via `pam_ssh_agent_auth`.
#
# ## How it works
#
#     sudo → pam_ssh_agent_auth → ssh-agent → PKCS#11 (tpm2-pkcs11) → TPM signs → ok
#
# - The key **never leaves the TPM** — it cannot be extracted from the machine.
# - Empty PIN → **zero manual steps** after the one-time setup.
# - `sudo` does not ask for a password: `pam_ssh_agent_auth` is inserted as `auth sufficient`, and
#   `nixpkgs` itself adds `Defaults env_keep+=SSH_AUTH_SOCK`.
#
# ## Flag
#
# `features.security.tpmSudo.enable` (default `false`). Enable it in `hosts/trantor/default.nix`. When
# enabled, the module `modules/security/tpm-sudo.nix`:
#
# - enables `security.tpm2` + `security.tpm2.pkcs11` + `tctiEnvironment`;
# - enables `security.pam.sshAgentAuth` + `sudo.sshAgentAuth`;
# - unlocks the kernel TPM modules (`kernel/params.nix`, `hosts/trantor/hardware.nix`);
# - adds `tpm2-pkcs11` to `agentPKCS11Whitelist` (`system/net/ssh.nix`);
# - creates the `tpm2-ssh-add.service` unit — auto-loads the key into the agent at login.
#
# ## Step 1 — enable fTPM in UEFI/BIOS
#
# `trantor` (Ryzen) has "AMD fTPM" / "PSP fTPM". In the BIOS: **Advanced → AMD fTPM configuration →
# TPM Device Selection → Firmware TPM** → Enabled.
#
# > Without this step the flag must not be enabled: the system will wait for the `tpmrm` device at
# > boot (the very pause because of which TPM was disabled).
#
# ## Step 2 — enable the flag
#
#     # hosts/trantor/default.nix
#     features.security.tpmSudo.enable = true;
#
# ## Step 3 — rebuild
#
#     just fmt && just check
#     nh os switch /etc/nixos#trantor --option substitute false
#
# ## Step 4 — verify the TPM
#
#     ls -l /dev/tpmrm0            # root:tss 0660
#     tpm2_getrandom 8 | xxd       # TPM responds with bytes
#     groups | grep -w tss         # user in the tss group
#
# ## Step 5 — create the key in the TPM (one-time)
#
#     tpm2_ptool init
#     tpm2_ptool addtoken --pid=1 --label=ssh --userpin= --sopin=
#     tpm2_ptool addkey --label=ssh --userpin= --algorithm=ecc256
#     ssh-keygen -D /run/current-system/sw/lib/libtpm2_pkcs11.so
#
# `ssh-keygen -D` prints the public part of the key (a line like `ecdsa-sha2-nistp256 AAAA...`). Empty
# PINs (`--userpin=`/`--sopin=`) are exactly what "no manual steps" means.
#
# ## Step 6 — add the public key to authorized_keys
#
# The file is root-owned, at `/etc/ssh/authorized_keys.d/neg` (the module uses `%u` → the calling
# user's name):
#
#     # paste the line from ssh-keygen -D:
#     sudo tee -a /etc/ssh/authorized_keys.d/neg
#     sudo chown root:root /etc/ssh/authorized_keys.d/neg
#     sudo chmod 0644 /etc/ssh/authorized_keys.d/neg
#
# Do not place the file in the home directory — that is a hole ([nixpkgs#31611]).
#
# ## Step 7 — verify
#
#     ssh-add -s /run/current-system/sw/lib/libtpm2_pkcs11.so   # manually, for verification
#     ssh-add -l                                                # the key is visible in the agent
#     sudo -k && sudo true                                      # no password is asked
#
# After re-login, `tpm2-ssh-add.service` picks the key up — manual `ssh-add` is no longer needed.
#
# ## Rollback
#
#     features.security.tpmSudo.enable = false;
#
#     nh os switch /etc/nixos#trantor --option substitute false
#
# TPM is disabled again: the modules are blacklisted, `/dev/tpmrm0` is not created, and `sudo` works
# with a password as before.
#
# ## Security and trade-offs
#
# - The key is non-exportable and bound to the hardware — the key file cannot be stolen.
# - **Empty PIN** means: the TPM signs for any process in the `tss` group (i.e. for processes of the
#   user `neg`). This protects against *key theft*, but not against *abuse from your own session* —
#   just like any passwordless sudo.
# - For stricter setups: set a PIN (`--userpin=...`); then `ssh-add -s` will ask for it once per
#   session (and `tpm2-ssh-add.service` for auto-loading will not do — a manual `ssh-add -s` is
#   needed). This requires one manual action.

##
# Module: security/tpm-sudo
# Purpose: Passwordless sudo with no manual actions, protected by the TPM.
#   A non-exportable SSH key stored in the TPM via tpm2-pkcs11 (empty PIN →
#   no interaction) is loaded into ssh-agent at login; `sudo` then
#   authenticates against that agent through pam_ssh_agent_auth instead of
#   asking for a password. The private key never leaves the TPM.
# Gate: features.security.tpmSudo.enable (default false). Enable fTPM in
#   UEFI/BIOS BEFORE flipping this on, otherwise boot stalls on the tpmrm
#   device wait. Full setup: the header of this module.
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
      # /etc/ssh/authorized_keys.d/neg — see the header of this module.
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
