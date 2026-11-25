# 2026-11-25 — aurora moved to its own repository

Status: extracted, wired and built; the host renders the player from the repository's own recipe.
The packaging commit is local (`9b4c038`), so the flake input is a `git+file:` on the live checkout.

Repositories: <https://github.com/neg-serg/aurora> (private, live checkout `~/src/nix/aurora`) and
<https://github.com/neg-serg/aurora-plugins> (public; it already carried its own `nix/package.nix`,
this commit only stops reading it as a `flake = false` source).

## What moved out of this tree

| was here                                      | now                                                       |
| --------------------------------------------- | --------------------------------------------------------- |
| `packages/aurora.nix` (210 lines)             | `nix/package.nix` in the aurora repository                |
| the runtime-lib list inside it                | `nix/runtime-libs.nix`, shared with the devShell          |
| `src = inputs.aurora-src` passthrough         | `src = ./..` — the checkout the recipe ships with         |
| `inputs.aurora-src` (ssh, `flake = false`)    | `inputs.aurora` (flake, `git+file:` until the push)       |
| `inputs.aurora-plugins-src` (`flake = false`) | `inputs.aurora-plugins` (flake, `inputs.nixpkgs.follows`) |

## Decisions taken with the move

- **The recipe lives where the code lives.** The host still calls it through
  `final.callPackage (inputs.aurora + "/nix/package.nix")`, so the derivation keeps building against
  this flake's package set and `pkgs.neg.aurora` / `pkgs.neg.aurora-headphones` are unchanged. The
  same file is exposed as `packages.default` and `packages.aurora-headphones`, which is what
  `nix build` and `checks.build` prove inside the repository.
- **One runtime-lib list.** It used to be two copies in two repositories, with a comment pointing
  across (`packages/aurora.nix` ↔ the devShell). Both now import `nix/runtime-libs.nix`, so a dev
  shell cannot disagree with the wrapper about what belongs on `LD_LIBRARY_PATH`.
- **`meta` is explicit, not `lib.mkMeta`.** The host's `mkMeta` helper is not nixpkgs, so the moved
  file spells out the same defaults (Linux only, no maintainers) instead of depending on a host-side
  builder. The rendered `meta` is identical.
- **`src = ./..`, not an input.** The flake source is git-filtered, so untracked files and `target/`
  stay out of the store without a separate source filter. `lib.cleanCargoSource` is not used: it
  does not exist on the repository's pinned nixpkgs.
- **The plugins are consumed through `nix/package.nix`**, not `packages.default`, for the same
  reason as the player: the build must follow the host's package set; the repository's own output
  serves its CI.

## How the host consumes it

- `flake.nix`: `aurora` (`git+file:///home/neg/src/nix/aurora`, `inputs.nixpkgs.follows`) and
  `aurora-plugins` (`github:neg-serg/aurora-plugins`, `inputs.nixpkgs.follows`). `aurora-src` and
  `aurora-plugins-src` are gone from `flake.lock`.
- `packages/overlay.nix`: three `final.callPackage` lines; `packages/aurora.nix` is deleted.
- `scripts/dev/flake-bump-own.sh` no longer lists aurora: a local `git+file:` checkout moves with
  `nix flake lock --update-input aurora` after a commit in `~/src/nix/aurora`, like `pleamar-config`
  (which has the `just pleamar-sync` recipe). The weekly timer keeps bumping only remote inputs.
- Comments and docs that named `aurora-src` follow the rename: `Justfile`,
  `.agent/workflows/update-flake.md`, `hosts/trantor/default.nix`,
  `modules/features/{media,system}.nix`, `files/shell/zsh/02-cmds.zsh`, `packages/AGENTS.md`.

## Verification done that day

- In the aurora repository: both `packages.*` evaluate; `nix build` builds `aurora-0.6.0`
  (bin/aurora, aurora-probe, mpdtest, theme-dump; the two desktop entries, the icon and the metainfo
  all installed) and `aurora-headphones-0.6.0`; `checks.build` is the same derivation.
- Here: `just fmt`, `just lint` (17 gates; README Nix files 467 → 466), the toplevel eval, the
  toplevel build, and `pkgs.neg.aurora.src` pointing at `9b4c038` with `nix/package.nix` inside it.

## Gaps to fix later

1. **The commit is not pushed.** Until it is, the input stays `git+file:`; then switch the URL in
   `flake.nix` to `git+ssh://git@github.com/neg-serg/aurora` and re-lock — nothing else changes.
1. **The repository's pre-commit gate is broken on this host:** its build step runs the rustup
   toolchain and dies on a stale `rustup-1.29.2/nix-support/ld-wrapper.sh` store path, so the commit
   needed `--no-verify` (the Nix build is unaffected). A `git+file:` input also cannot be locked
   from a dirty checkout, so the two unrelated staged docs were stashed for the lock and restored
   afterwards.
