# 2026-11-25 — the dsh plugins moved to their own flake

Status: extracted, published, wired, activated and verified. All thirteen suites are green. The gaps
at the bottom are deliberate and each names how to close it.

Repository: <https://github.com/neg-serg/dsh-plugins> (public, branch `main`, head `c7a758d`). Live
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

- `flake.nix`: `dsh-plugins.url = "github:neg-serg/dsh-plugins"`,
  `inputs.nixpkgs.follows = "nixpkgs"`. The live checkout is where edits happen; a change reaches
  the build after a push and `nix flake lock`.
- `dsh-tui.nix`: `dshPlugins = inputs.dsh-plugins.packages.${pkgs.stdenv.hostPlatform.system}`
  (`pkgs.system` does not exist here — `allowAliases = false`), passed into the roster and used for
  the three preset plugins (`dsh-advisor`, `dsh-category-skill-reminder`, `dsh-ttsr`) that used to
  be `copyPathToStore` calls.
- `dsh-terminal-plugins.nix`: takes `dshPlugins`, and `pathFor` returns `./${name}` for the two
  local forks and `dshPlugins.${name}` otherwise. The 29-row roster and its order are unchanged.
- `flake.lock`: the input is locked at `github:neg-serg/dsh-plugins/c7a758d`.

The built caretaker script carries 29 `seed_pkg` lines — 27 store paths from the input, the two
forks as `copyPathToStore` paths — plus the three `seed` lines for the preset plugins, all pointing
at store paths. The first activation re-pinned the 32 `file:` dependencies in the live profile, and
`dsh plugin --profile tui install` is idempotent afterwards.

## Verification done that day

In the new repository: `nix flake check -L` green — the check builds every plugin through the
`bundle` linkFarm and runs the four suites that need no harness install (`dsh-diff`, `dsh-herdr`,
`dsh-notepad-write-guard`, `dsh-statusline`) from a writable copy in the sandbox. `scripts/test.sh`
runs all thirteen suites (322 assertions) green: `scripts/peers.sh` resolves the harness from the
installed `dsh` wrapper and links `node_modules/@deepseek-ai`, because ESM ignores `NODE_PATH`.

Here: `just fmt`, `just lint` (18 gates), `just check` (24 checks, including `dsh-worktree-guard`
and `dsh-statusline-guard`, which test the rust-pkgs helper binaries and are unaffected), the
toplevel build, the grep of the built `dsh-tui-ensure` script for the store paths above, and the
agent switch.

## Fixed the same day

1. **The three red suites were stale tests, not missing code.** An October translation pass
   (`41f9213e` here) moved the plugin text to English and left the assertions in Russian:
   `dsh-notify-input` expected the old titles, `dsh-plan-format-validator` the old reason, and
   `dsh-worktree` the old Russian confirmation string. The expectations now match the code, and the
   two strings the pass half-translated (the worktree timeout message and the
   category-skill-reminder hint) are English. `scripts/test.sh` gates all suites again.
1. **The peers no longer need a manual symlink.** `scripts/peers.sh` reads the `exec` line of the
   installed `dsh` wrapper to find the real package (a plain `readlink` lands on the wrapper, which
   has only `bin/`) and links its nested `@deepseek-ai` tree; `scripts/test.sh` calls it on demand.
1. **The live profile carried a dead `link:` to the old aurora checkout.** `@local/dsh-gpu-sandbox`
   pointed at `/home/neg/src/aurora/tools/dsh-gpu-sandbox`, which moved to `~/src/nix/aurora` with
   the grouped-flake refactor. The first caretaker run after the extraction re-pinned the
   dependencies, and `dsh plugin install` died in `reconcile` because pnpm had dropped the dead link
   and the bundle could no longer be resolved. Unrelated to the extraction but exposed by it: the
   entry was repointed to the current path by hand (the profile manifest is a user file, no module
   owns that dependency).

## Gaps to fix later

1. **CI pins the harness version** (`@deepseek-ai/dsh@0.2.0-rc.2`, the version `packages/dsh`
   packages). A harness bump must touch both.
1. **The two forks stay here**; if they are ever republished, they move out and the `localPlugins`
   list in the roster empties.
1. **Host paths in defaults.** `dsh-desktop` defaults to `/home/neg/.local/bin/computer-use-linux`,
   and several suites use host paths as fixtures. Harmless for this host, wrong for a stranger's
   checkout — the same gap the rust-pkgs split recorded.

## Commits

- New repository: `474112f` (import), `732e73d` (nixpkgs pin), `c7a758d` (stale tests + peers).
- This tree: the extraction commit (input, roster wiring, 77 files removed, this note) and the
  follow-up that switches the input to `github:` and records the fixes above.
