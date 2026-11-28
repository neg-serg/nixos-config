______________________________________________________________________

## description: Rebuild NixOS configuration

# Rebuild NixOS

## Quick Command

```bash
just deploy
```

`deploy` builds the host toplevel through rom (the build-graph monitor), updates
`/nix/var/nix/profiles/system` and runs `switch-to-configuration switch` — the same steps as
`nixos-rebuild switch`, with the build rendered as a graph.

On trantor the watcher may already deploy a clean committed `main`; the manual paths below are for
uncommitted work, risky paths and failures.

## Steps

1. **Check configuration**:

   ```bash
   just check
   ```

1. **Build without switching**:

   ```bash
   rom build .#nixosConfigurations.trantor.config.system.build.toplevel \
     -- --out-link result
   ```

1. **Switch to new generation**:

   ```bash
   just deploy
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

On this host do not call `sudo nixos-rebuild switch`: the build runs as root, which cannot fetch the
private `aurora` `git+ssh` input (see "Human switch" below). The non-interactive paths are
`just switch-sudo` and `just agent-switch`; both build as the invoking user and never call
`nixos-rebuild`.

The stdin caveat still matters where `nixos-rebuild` is usable at all. It re-execs itself through
`systemd-run --pipe`, which forwards its own stdin into the transient unit. When the caller's stdin
is a **socket** (an agent's tool shell, some CI runners) systemd refuses it:

```
Failed to start transient service unit: StandardInputFileDescriptor passed is of
incompatible type: Protocol wrong type for socket
```

The build succeeds and nothing is applied, so redirect stdin from `/dev/null`:

```bash
sudo nixos-rebuild switch --flake .#trantor < /dev/null
```

That redirect does not help on trantor: the private input fails first. Use the recipes.

## Who runs it

Two paths, preferred one first:

1. **Agent rollout (no password).** `features.security.agentSwitch` (on by default) installs a
   root-owned oneshot unit plus a polkit rule that lets the main user start exactly
   `nixos-agent-rollout.service` (`modules/security/agent-switch.nix`) — polkit, not setuid sudo, so
   the trigger also works from a session sandbox. The unit re-builds the flake as the main user
   (root's libgit2 refuses a user-owned repository) and activates the verified store path as root;
   it **refuses** when the tree no longer builds the toplevel named in
   `/etc/nixos/.agent/switch-request`, and removes the request on success:

   ```bash
   cd /etc/nixos
   just fmt && just lint
   rom build .#nixosConfigurations.trantor.config.system.build.toplevel \
     -- --out-link result
   just agent-switch "$(readlink -f result)"   # request + start unit + tail the journal
   ```

   The run lands in the journal: HEAD, the dirty-file list (the tree *is* what gets activated), the
   artifact and the activation output — `journalctl -u nixos-agent-rollout`.

   The unit file is a constant string: it must never contain a store path, otherwise a switch that
   rebuilds one of those paths would stop the unit that is running the switch (2026-10-17: an
   activation died on `status=15/TERM` this way). The `nixos-agent-switch` name is the pre-rename
   unit, kept byte-identical for one generation by a bootstrap block in the module.

1. **Human switch.** Use it when the mechanism is off, not activated yet, or when the change *is*
   the mechanism:

   ```bash
   just switch-sudo
   ```

   The recipe builds with the invoking user's credentials and gives root only `nix-env --set` on
   `/nix/var/nix/profiles/system` plus `switch-to-configuration`. A root-side build is not possible
   here: `aurora` is a private `git+ssh` flake input and root has no access to it, while the fetcher
   clones a git input on every evaluation (root's per-user fetcher cache stays empty even after the
   user built the same tree). `sudo nixos-rebuild switch` therefore stops at
   `error: Failed to fetch git repository 'ssh://git@github.com/neg-serg/aurora'` — measured
   2026-11-26 17:15:48, twelve seconds in, and the same failure hit the agent unit on 2026-11-25.

`sudo` stays password-gated for everything else: the `nixos-rebuild` and `env *` NOPASSWD entries
were removed on purpose (`modules/security/default.nix` — passwordless arbitrary root, since the
activated flake is user-writable), and `features.security.tpmSudo` is off on this host. The
agent-switch mechanism is the one deliberate exception, and it is narrow: a single polkit rule for
one unit and the `start` verb, verified artifact only. Never add `-n` to other sudo commands.

## Automatic rollout (watcher)

`features.system.rolloutWatch` (enabled on trantor, `hosts/trantor/default.nix`) runs
`nixos-rollout-watch` every two minutes in the user manager
(`modules/user/nix-maid/sys/user-services/rollout-watch.nix`). For a new commit on a clean `main` it
runs `just check`, builds the host toplevel and writes the verified store path to
`.agent/switch-request` — the same request an agent makes by hand above — then starts
`nixos-agent-rollout` itself and waits for the result. The report goes to ntfy, the desktop and
Telegram.

Changes under `secrets/`, `modules/system/net/vpn/`, `modules/security/` and the watcher itself are
**not** deployed automatically: the report asks for `just switch-sudo` instead, because a wrong
secret/VPN/security-module change can lock the host out.

- state (`head`, `status`, `base`, the last `check.log`/`build.log`):
  `~/.local/state/nixos-rollout-watch/`
- journal: `journalctl --user -u nixos-rollout-watch`
- pause: `systemctl --user stop nixos-rollout-watch.timer`
- a manual switch, an agent rollout or a rollback between two ticks rebases the watcher on HEAD and
  sends nothing — it never deploys over a deliberate human action.
