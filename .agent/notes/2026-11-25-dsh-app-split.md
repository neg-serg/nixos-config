# 2026-11-25 — dsh moved to its own repository

Status: extracted, published (`github:neg-serg/dsh-app`, `4c4eeba`), wired and built. The package is
byte-identical to the one that was in this tree (`/nix/store/wl1andmv…-dsh-0.2.0-rc.2`), so the move
itself changes nothing at runtime.

Repository: <https://github.com/neg-serg/dsh-app> (public). Live checkout: `~/src/nix/dsh-app`.

## What moved out of this tree

| was here                              | now                                  |
| ------------------------------------- | ------------------------------------ |
| `packages/dsh/default.nix`            | `package.nix` at the repository root |
| `packages/dsh/nodejs-official.nix`    | `nodejs-official.nix`                |
| `packages/dsh/post-install.sh`        | `post-install.sh`                    |
| `packages/dsh/package-lock.json`      | `package-lock.json`                  |
| `apps/dsh-terminal-plugins.nix`       | `tui/roster.nix`                     |
| `apps/dsh-presets.nix`                | `tui/presets.nix`                    |
| `apps/dsh-tui-ensure.sh`              | `tui/ensure.sh`                      |
| `apps/dsh-xdg-migrate.sh`             | `tui/xdg-migrate.sh`                 |
| `apps/dsh-tui-assets/themes/neg.json` | `tui/themes/neg.json`                |
| `apps/dsh-fast/`                      | `tui/presets/fast/`                  |
| `apps/dsh-liangshen-fork/`            | `tui/presets/liangshen/`             |

## Decisions taken with the move

- **The host keeps the machine, the repository keeps the harness.** Units and activation
  (`dsh-tui.nix`), the sops-backed wrapper, the free-route smoke test (`dsh.nix`) and the two
  third-party plugin forks stay here; the recipe and the profile *data* left.
- **The roster takes its local forks as an argument.** It used to resolve `./${name}` for
  `dsh-plugin-recall` and `dsh-plugin-vetting`; from another flake that path would be wrong, so the
  host passes `localForks` and the roster falls back to `dshPlugins.<name>` for everything else.
- **The patcher is still passed in.** `dsh-patch` belongs to `rust-pkgs`; the host calls
  `final.callPackage (inputs.dsh-app + "/package.nix") { inherit (final.neg) dsh-patch; }`, so the
  built harness keeps using this tree's patcher and the repository needs no second copy. The
  repository's own flake follows `rust-pkgs` only for `nix build`/`checks.build`.
- **The package file is unchanged, on purpose.** `package.nix` still renders `post-install.sh`,
  reads `package-lock.json` and calls `./nodejs-official.nix`; only its location moved, which is why
  the derivation hash is the same.
- **`apps/default.nix` lost its exclusion list.** It existed only for the two data modules that are
  gone, so `neg.importDir` now walks the directory with no exceptions.

## How the host consumes it

- `flake.nix`: `dsh-app` (`github:neg-serg/dsh-app`, `inputs.nixpkgs.follows`,
  `inputs.rust-pkgs.follows`).
- `packages/overlay.nix`: one `final.callPackage` line; `pkgs.neg.dsh` unchanged.
- `modules/user/nix-maid/apps/dsh-tui.nix`: one `dshApp = inputs.dsh-app` binding, imported by the
  roster, the presets, the caretaker, the XDG migration and the theme path.
- Comments that named the old files follow the move (`dsh.nix`, `dsh-acp.nix`, `free-llm-check.sh`,
  the two fork `cordis.patch.yml` files, `.ignore`, the search config).
- README statistics: 466 → 462 Nix files, 359 → 357 module files.

## Verification done that day

- In the repository: `nix build .#default` (same `wl1andmv…-dsh-0.2.0-rc.2` as the host had),
  `nix flake check` builds `checks.build` from the same file.
- Here: `just fmt`, `just lint` (17 gates), the toplevel eval and build, the switch, and the
  rendered caretaker checked for leftover `@placeholder@` markers.

## Gaps to fix later

1. **The roster and presets are host-shaped data in a public repository.** They carry this host's
   plugin allow-list and the `neg` preset text; nothing secret, but a second host would fork the
   files rather than reuse them.
1. **`dsh` version bumps still touch two places in spirit:** the recipe's `version`/hashes move to
   the repository, but the wrapper and the unit stay here, so a major harness change still needs a
   look at `dsh.nix`.
