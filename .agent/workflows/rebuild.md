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

Two paths, preferred one first:

1. **Agent rollout (no password).** `features.security.agentSwitch` (on by default) installs a
   root-owned oneshot unit plus a polkit rule that lets the main user start exactly
   `nixos-agent-switch.service` (`modules/security/agent-switch.nix`) — polkit, not setuid sudo, so
   the trigger also works from a session sandbox. The unit re-builds the flake as the main user
   (root's libgit2 refuses a user-owned repository) and activates the verified store path as root;
   it **refuses** when the tree no longer builds the toplevel named in
   `/etc/nixos/.agent/switch-request`, and removes the request on success:

   ```bash
   cd /etc/nixos
   just fmt && just lint
   nix build .#nixosConfigurations.trantor.config.system.build.toplevel \
     --out-link result --option substitute false
   just agent-switch "$(readlink -f result)"   # request + start unit + tail the journal
   ```

   The run lands in the journal: HEAD, the dirty-file list (the tree *is* what gets activated), the
   artifact and the activation output — `journalctl -u nixos-agent-switch`.

1. **Human switch.** Use it when the mechanism is off, not activated yet, or when the change *is*
   the mechanism:

   ```bash
   sudo nixos-rebuild switch --flake .#trantor --option substitute false < /dev/null
   ```

`sudo` stays password-gated for everything else: the `nixos-rebuild` and `env *` NOPASSWD entries
were removed on purpose (`modules/security/default.nix` — passwordless arbitrary root, since the
activated flake is user-writable), and `features.security.tpmSudo` is off on this host. The
agent-switch mechanism is the one deliberate exception, and it is narrow: a single polkit rule for
one unit and the `start` verb, verified artifact only. Never add `-n` to other sudo commands.
