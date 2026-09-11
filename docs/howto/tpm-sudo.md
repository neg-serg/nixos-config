# TPM-sudo — passwordless sudo via TPM (no manual steps)

How to get `sudo` without typing a password yet with protection: the private SSH key lives **inside
the TPM** (non-exportable) and signs requests without a PIN; `sudo` authenticates through the
ssh-agent via `pam_ssh_agent_auth`.

## How it works

```
sudo → pam_ssh_agent_auth → ssh-agent → PKCS#11 (tpm2-pkcs11) → TPM signs → ok
```

- The key **never leaves the TPM** — it cannot be extracted from the machine.
- Empty PIN → **zero manual steps** after the one-time setup.
- `sudo` does not ask for a password: `pam_ssh_agent_auth` is inserted as `auth sufficient`, and
  `nixpkgs` itself adds `Defaults env_keep+=SSH_AUTH_SOCK`.

## Flag

`features.security.tpmSudo.enable` (default `false`). Enable it in `hosts/odin/default.nix`. When
enabled, the module `modules/security/tpm-sudo.nix`:

- enables `security.tpm2` + `security.tpm2.pkcs11` + `tctiEnvironment`;
- enables `security.pam.sshAgentAuth` + `sudo.sshAgentAuth`;
- unlocks the kernel TPM modules (`kernel/params.nix`, `hosts/odin/hardware.nix`);
- adds `tpm2-pkcs11` to `agentPKCS11Whitelist` (`system/net/ssh.nix`);
- creates the `tpm2-ssh-add.service` unit — auto-loads the key into the agent at login.

## Step 1 — enable fTPM in UEFI/BIOS

`odin` (Ryzen) has "AMD fTPM" / "PSP fTPM". In the BIOS: **Advanced → AMD fTPM configuration → TPM
Device Selection → Firmware TPM** → Enabled.

> Without this step the flag must not be enabled: the system will wait for the `tpmrm` device at
> boot (the very pause because of which TPM was disabled).

## Step 2 — enable the flag

```nix
# hosts/odin/default.nix
features.security.tpmSudo.enable = true;
```

## Step 3 — rebuild

```bash
just fmt && just check
nh os switch /etc/nixos#odin --option substitute false
```

## Step 4 — verify the TPM

```bash
ls -l /dev/tpmrm0            # root:tss 0660
tpm2_getrandom 8 | xxd       # TPM responds with bytes
groups | grep -w tss         # user in the tss group
```

## Step 5 — create the key in the TPM (one-time)

```bash
tpm2_ptool init
tpm2_ptool addtoken --pid=1 --label=ssh --userpin= --sopin=
tpm2_ptool addkey --label=ssh --userpin= --algorithm=ecc256
ssh-keygen -D /run/current-system/sw/lib/libtpm2_pkcs11.so
```

`ssh-keygen -D` prints the public part of the key (a line like `ecdsa-sha2-nistp256 AAAA...`). Empty
PINs (`--userpin=`/`--sopin=`) are exactly what "no manual steps" means.

## Step 6 — add the public key to authorized_keys

The file is root-owned, at `/etc/ssh/authorized_keys.d/neg` (the module uses `%u` → the calling
user's name):

```bash
# paste the line from ssh-keygen -D:
sudo tee -a /etc/ssh/authorized_keys.d/neg
sudo chown root:root /etc/ssh/authorized_keys.d/neg
sudo chmod 0644 /etc/ssh/authorized_keys.d/neg
```

Do not place the file in the home directory — that is a hole ([nixpkgs#31611]).

## Step 7 — verify

```bash
ssh-add -s /run/current-system/sw/lib/libtpm2_pkcs11.so   # manually, for verification
ssh-add -l                                                # the key is visible in the agent
sudo -k && sudo true                                      # no password is asked
```

After re-login, `tpm2-ssh-add.service` picks the key up — manual `ssh-add` is no longer needed.

## Rollback

```nix
features.security.tpmSudo.enable = false;
```

```bash
nh os switch /etc/nixos#odin --option substitute false
```

TPM is disabled again: the modules are blacklisted, `/dev/tpmrm0` is not created, and `sudo` works
with a password as before.

## Security and trade-offs

- The key is non-exportable and bound to the hardware — the key file cannot be stolen.
- **Empty PIN** means: the TPM signs for any process in the `tss` group (i.e. for processes of the
  user `neg`). This protects against *key theft*, but not against *abuse from your own session* —
  just like any passwordless sudo.
- For stricter setups: set a PIN (`--userpin=...`); then `ssh-add -s` will ask for it once per
  session (and `tpm2-ssh-add.service` for auto-loading will not do — a manual `ssh-add -s` is
  needed). This requires one manual action.
