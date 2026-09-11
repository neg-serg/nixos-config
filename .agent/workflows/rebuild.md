______________________________________________________________________

## description: Rebuild NixOS configuration

# Rebuild NixOS

## Quick Command

```bash
sudo nixos-rebuild switch --flake .#odin
```

## Steps

1. **Check configuration**:

   ```bash
   just check
   ```

1. **Build without switching**:

   ```bash
   nixos-rebuild build --flake .#odin
   ```

1. **Switch to new generation**:

   ```bash
   sudo nixos-rebuild switch --flake .#odin
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
sudo -n nixos-rebuild switch --flake .#odin --option substitute false < /dev/null
```

Keep the redirect in any scripted rollout.
