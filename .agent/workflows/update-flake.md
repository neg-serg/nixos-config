______________________________________________________________________

## description: Update flake inputs to latest versions

# Update Flake

## Update All Inputs

```bash
nix flake update
```

## Update Specific Input

```bash
nix flake lock --update-input nixpkgs
```

## Update Only My Inputs

`just bump-own` bumps just the inputs that are neg's own repositories. Each bump is kept only when
the trantor toplevel still evaluates; a failing bump is reverted and listed. The result is one
`[flake] Bump own project inputs` commit, never pushed: review it and push by hand. `rollout-watch`
deploys the commit on its next tick once the tree is clean.

```bash
just bump-own              # seven light inputs; commit when the eval passes
just bump-own --all        # also aurora-src and iosevka-neg (long rebuilds)
just bump-own --no-commit  # leave flake.lock modified for review
```

The recipe refuses a dirty tree or a branch other than `main`, and never touches `nixpkgs` or
third-party pins.

## Common Inputs

| Input | Description | |-------|-------------| | `nixpkgs` | Main package repository | | `sops-nix`
| Secrets management |

## Rebuild After Update

```bash
sudo nixos-rebuild switch --flake .#trantor
```

## Rollback

If update breaks something:

1. **List generations**:

   ```bash
   sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
   ```

1. **Switch to previous**:

   ```bash
   sudo nixos-rebuild switch --rollback
   ```

## Check Changelog

After updating nixpkgs:

```bash
dix /run/current-system result
```
