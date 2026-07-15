______________________________________________________________________

## name: nixos-commit description: "Commit NixOS config changes with proper bracketed scope format. Use after making changes that need to be committed."

# NixOS Commit

Commit changes following this repository's conventions.

## Check State First

```bash
git status
git diff --stat
git log -5 --oneline
```

## Commit Message Format

```
[scope] Short imperative description without period
```

### Examples from this repo

| Scope | Example | |-------|---------| | nixpkgs |
`[nixpkgs] Revert from nixpkgs-weekly to stable nixos-26.05` | | core/modules |
`[core/modules] Add domainFilter for parallel eval; remove dead flat.nix` | | flake/eval |
`[flake/eval] Wire per-profile domainFilter specialArgs; add module checks` | | dev/ai |
`[dev/ai] Add herdr agent multiplexer` | | dev/opencode | `[dev/opencode] Add Pi coding agent` | |
hardware/bluetooth | `[hardware/bluetooth] Enable bluetooth and add bluetui TUI client` | | docs |
`[docs] Document audio creation stack` | | hosts/odin | `[hosts/odin] Tune cooling profile` |

### Common scopes

- nixpkgs, flake/*, core/*
- hosts/<hostname>
- dev/*, cli/*, hardware/*, media/*, servers/\*
- modules/*, packages/*
- docs, ci, refactor

## Workflow

1. Stage related changes together (avoid mixing unrelated changes)
1. Commit with `[scope] Short description`
1. Run `just fmt` before committing
1. Verify with `just check` after committing
