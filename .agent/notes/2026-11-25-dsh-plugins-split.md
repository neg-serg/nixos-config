# 2026-11-25 — the dsh plugins moved to their own flake

Status: extracted, committed, wired and verified; not pushed yet. The gaps at the bottom are
deliberate and each names how to close it.

Repository: `github:neg-serg/dsh-plugins` (to be pushed, branch `main`, head `732e73d`). Live
checkout: `/home/neg/src/nix/dsh-plugins`.

## What moved out of this tree

The 30 plugin directories under `modules/user/nix-maid/apps/dsh-*` that the host owns — 77 files of
`package.json`, `lib/` and `test.mjs`. They now live as `plugins/<name>/` in the new repository.

Two neighbours stayed on purpose:

- `dsh-plugin-recall` and `dsh-plugin-vetting` are forks of `truelove-dreamer`'s packages (their
  manifests still point at his repositories). Republishing them is a licensing decision, not a
  packaging one, so they keep living here and the roster resolves them to a source directory.
- `dsh-liangshen-fork`, `dsh-tui-assets` and `dsh-fast` are preset and asset material, not plugins.

The host glue also stays: the roster and loader rows (`dsh-terminal-plugins.nix`), the profile
caretaker (`dsh-tui.nix`, `dsh-tui-ensure.sh`), the preset declarations (`dsh-presets.nix`) and the
`dsh` harness packaging (`packages/dsh`).

## How the repository is packaged

One builder, `package.nix`, parameterised by `name`; no per-plugin `package.nix` and no generated
list. `flake.nix` names the 30 plugins explicitly, the same allow-list reasoning the roster uses
(`builtins.readDir` would let a stray directory become a package).

The derivation is a copy, not a build: the plugin directory becomes a store path with `package.json`
and `lib/` at its root. That is the shape the host already expected from the source directory,
because `dsh-tui-ensure.sh` uses it twice — as a `file:` dependency it re-pins on every rebuild, and
as the repair source for a profile copy pnpm's reconciliation walked off.

`test.mjs` ships in the store too: the packaging is a copy, and hiding the suite would make the
shipped tree differ from the one the tests run against.

## How the host consumes it

- `flake.nix`: `dsh-plugins.url = "git+file:///home/neg/src/nix/dsh-plugins"`,
  `inputs.nixpkgs.follows = "nixpkgs"`. It becomes `github:neg-serg/dsh-plugins` once pushed.
- `dsh-tui.nix`: `dshPlugins = inputs.dsh-plugins.packages.${pkgs.stdenv.hostPlatform.system}`
  (`pkgs.system` does not exist here — `allowAliases = false`), passed into the roster and used for
  the three preset plugins (`dsh-advisor`, `dsh-category-skill-reminder`, `dsh-ttsr`) that used to
  be `copyPathToStore` calls.
- `dsh-terminal-plugins.nix`: takes `dshPlugins`, and `pathFor` returns `./${name}` for the two
  local forks and `dshPlugins.${name}` otherwise. The 29-row roster and its order are unchanged.
- `flake.lock`: one new input node, locked at `732e73d`.

The built caretaker script carries 29 `seed_pkg` lines — 27 store paths from the input, the two
forks as `copyPathToStore` paths — plus the three `seed` lines for the preset plugins, all pointing
at store paths.

## Verification done that day

In the new repository: `nix flake check -L` green. The check builds every plugin through the
`bundle` linkFarm and runs the four suites that need no harness install (`dsh-diff`, `dsh-herdr`,
`dsh-notepad-write-guard`, `dsh-statusline`) from a writable copy in the sandbox.
`bash scripts/test.sh` with the harness peers on `node_modules/@deepseek-ai` runs the other 10 gated
suites green.

Here: `just fmt`, `just lint` (18 gates), `just check` (24 checks, including `dsh-worktree-guard`
and `dsh-statusline-guard`, which test the rust-pkgs helper binaries and are unaffected), the
toplevel build, and a grep of the built `dsh-tui-ensure` script for the store paths above.

## Gaps to fix later

1. **Three suites are red** on the extraction baseline and are named, not skipped, in the new
   repository's `scripts/test.sh` and README: `dsh-notify-input` (4 assertions — the configured
   notification titles never reach the terminal), `dsh-plan-format-validator` (2 — the rejection
   reason names neither the heading nor the sections) and `dsh-worktree` (1 — a silent success
   prints no confirmation).
1. **Not pushed.** The host consumes a `git+file:` input; switch it to `github:` after the push.
1. **Local test runs need the peers by hand.** ESM ignores `NODE_PATH`, so the repository README
   documents the `node_modules/@deepseek-ai` symlink against a dsh install.
1. **CI pins the harness version** (`@deepseek-ai/dsh@0.2.0-rc.2`, the version `packages/dsh`
   packages). A harness bump must touch both.
1. **The two forks stay here**; if they are ever republished, they move out and the `localPlugins`
   list in the roster empties.

## Commits

- New repository: `474112f` (import), `732e73d` (nixpkgs pin).
- This tree: the extraction commit (input, roster wiring, 77 files removed, this note).
