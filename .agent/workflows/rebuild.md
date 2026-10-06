______________________________________________________________________

## description: Rebuild NixOS configuration

# Rebuild NixOS

## Quick Command

```bash
sudo nixos-rebuild switch --flake .#trantor --option substitute false < /dev/null
```

## Steps

1. **Check configuration**:

   ```bash
   just check
   ```

1. **Build without switching**:

   ```bash
   nixos-rebuild build --flake .#trantor
   ```

1. **Switch to new generation**:

   ```bash
   sudo nixos-rebuild switch --flake .#trantor
   ```

## Options

| Flag | Description | |------|-------------| | `--flake .#host` | Use flake for host | |
`--show-trace` | Show error trace | | `--dry-run` | Preview changes | | `--upgrade` | Update flake
inputs |

## Troubleshooting

If build fails:

```bash
just lint      # Check for errors
just check     # Run all checks
```

## Non-interactive runs (agents, CI)

`nixos-rebuild switch` re-execs itself through `systemd-run --pipe`, which forwards its own stdin
into the transient unit. When the caller's stdin is a **socket** (an agent's tool shell, some CI
runners) systemd refuses it:

```
Failed to start transient service unit: StandardInputFileDescriptor passed is of
incompatible type: Protocol wrong type for socket
```

The build succeeds and nothing is applied, so retrying with stdin redirected from `/dev/null` is the
whole fix:

```bash
sudo nixos-rebuild switch --flake .#trantor --option substitute false < /dev/null
```

Keep the redirect in any scripted rollout.

## Who runs it

`sudo` asks for a password: the `nixos-rebuild` NOPASSWD entry was removed on purpose
(`modules/security/default.nix` — it was passwordless arbitrary root, since the activated flake is
user-writable), and `features.security.tpmSudo` is off on this host. So an agent prepares the
rollout and builds the closure, then the user runs the switch. Never add `-n` to the switch command:
with no NOPASSWD rule `sudo -n` fails immediately instead of prompting.

Agent-side preparation (everything that needs no root):

```bash
cd /etc/nixos
git status                 # must be clean/intentional — the working tree is what gets activated
just fmt && just lint
nix build .#nixosConfigurations.trantor.config.system.build.toplevel \
  --out-link result --option substitute false
ls -l result               # then grep the store paths it points at to verify the change landed
```
