# 2026-11-25 — the Nix builds moved to nix-optimized

Status: extracted, published, wired and verified. The extraction is derivation-identical: both
packages produce the same `drvPath` they produced inside this tree, so the switch changed no store
path and did not rebuild Nix.

Repository: <https://github.com/neg-serg/nix-optimized> (public, branch `main`, head `e3a30b5`).
Live checkout: `/home/neg/src/nix/nix-optimized`.

## What moved out of this tree

| was here                                                    | now                                                                                         |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `packages/nix-eval-patched/{default.nix,patches/,smoke.sh}` | `nix-eval-patched/{package.nix,patches/,smoke.sh}`                                          |
| `packages/nix-det-pgo/{default.nix,patches/,workload.nix}`  | `nix-det-pgo/{package.nix,patches/,workload.nix}`                                           |
| —                                                           | `flake.nix`, `flake.lock`, `README.md`, `LICENSE`, `.gitignore`, `.github/workflows/ci.yml` |

The host keeps the names and the wiring: `pkgs.neg.nix-eval-patched` and `pkgs.neg.nix-det-pgo` are
still what `packages/flake/custom-packages.nix`, `modules/nix/nix-pgo.nix` and
`features.nix.pgoNix.enable` address.

## Packaging decisions taken with the move

- **`nix-det-pgo` takes `nix-src` explicitly** instead of a whole `inputs` set: `callPackage` fills
  it at both call sites, and the dependency is visible where the package is wired.
  `nix-eval-patched` was already self-contained (`{ nixVersions }`).
- **The patch lists are exported through `passthru.patchFiles`**, so the flake checks apply exactly
  the stack the package builds. Both checks are real applications (`applyPatches`), not dry runs:
  they fail in about half a minute when nixpkgs or Determinate moves, instead of at the end of a
  12-minute build.
- **`prev.callPackage`, not `final.callPackage`.** The package reads `pkgs.nixDependencies` and the
  modular nix components; building it from the final fixpoint changed every component derivation
  even though the output tree is the same, i.e. a full PGO rebuild for nothing. The call shape the
  packages had in `packages/overlays/dev.nix` is preserved, and the overlay says why.
- **`workload.nix` is byte-identical to the original.** It is interpolated into the training script,
  so its store path is part of the PGO profile derivation and of every component that consumes the
  profile: a comment-only edit changed all of them (found by comparing `drvPath`s, fixed in
  `e3a30b5`).

## How the host consumes it

- `flake.nix`: `nix-optimized.url = "github:neg-serg/nix-optimized"`, with
  `inputs.nixpkgs.follows = "nixpkgs"` and `inputs.nix-src.follows = "nix-src"` (the PGO build must
  use the same Determinate tree the system ships).
- `packages/overlays/dev.nix`:
  `prev.callPackage (inputs.nix-optimized + "/nix-det-pgo/package.nix") { inherit (inputs) nix-src; }`
  and the same shape for `nix-eval-patched`.
- `flake.lock`: one input node, locked at `e3a30b5`; `nix-optimized/nix-src` follows the host's
  `nix-src`.

## Verification done that day

- **`drvPath` equality with the pre-extraction baseline** (the point of the exercise):
  `nix-eval-patched` = `dzf88gp84s29n436lqcs8zsn37vm0j5w-nix-2.35.6+12.drv`, `nix-det-pgo` =
  `3730jm18lhjq3qzsj1s7s6i1s281yhn0-nix-2.35.3+4.drv`, both unchanged. The running `nix.package` is
  therefore the same store path.
- In the new repository: `nix flake check -L` builds `patch-stack` (the twelve patches applying to
  nixpkgs' 2.35.6 source) and `determinate-patches` (the four applying to the pinned `nix-src`);
  `nix build --dry-run` evaluates both packages. CI is green on both commits.
- Here: `just fmt`, `just lint` (the README statistics drop 517 → 514 Nix files and 148 → 147
  packages), `just check`, the toplevel build and the switch.

## Gaps to fix later

1. **CI never builds the packages.** The full builds take minutes each and the functional suites
   want a real daemon, so CI proves evaluation and patch application only; the acceptance runs stay
   host-side (`smoke.sh`, the A/B numbers in the package headers).
1. **`smoke.sh` is a host tool.** It compares against `/etc/nixos` and talks to the running daemon
   by design; it is not portable and is not in CI.
1. **The patch stacks are cut against specific revisions** (2.35 plus #16244; Determinate 3.23.3).
   The bump checklists live in the package headers; a stale stack now fails `nix flake check` first.
1. **`nix-eval-patched` is still not `nix.package`**, deliberately: it is upstream Nix and does not
   know `lazy-trees`.

## Commits

- New repository: `74deb4c` (import), `e3a30b5` (workload.nix restored).
- This tree: the extraction commit (input, overlay, 3 Nix files removed here, comment updates,
  README statistics, this note).
