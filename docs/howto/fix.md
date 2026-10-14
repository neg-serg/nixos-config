# `fix` — fast Nix evaluator (patched master)

`fix` is a from-scratch Nix-language evaluator in Zig
([psyclyx/fix](https://github.com/psyclyx/fix)) that speaks the Nix daemon protocol, so it can
evaluate, build and (with `fix switch`) activate a configuration. The package lives in
`packages/fix/` and is enabled per host with `features.cli.fix.enable = true` (on trantor:
`hosts/trantor/default.nix`).

## Why master, not the release

The last release (`v0.3.0`, 2026-08-03) cannot read this repo's `flake.lock`: it fails with
`InvalidFlakeLock` on locks that carry `follows` chains (`packages/fix/default.nix` pins a master
commit instead, which contains the upstream parser fix). Two local fixes ride on top as
`packages/fix/patches/0001-*.patch`:

- a bare path that is a git work-tree root resolves as `git+file` whenever the tree is written to
  the store (`instantiate`/`build`/`switch`), like Nix — the old raw-directory copy pulled `.git`,
  caches and build output into the store and died with `StreamTooLong` on the 283 MB blob under
  `.agent/`; plain `eval` still reads the local directory in place;
- pure eval omits `builtins.currentSystem` / `builtins.currentTime` (and `setPureEval` rebuilds the
  `builtins` attrset), so flake-compat guards like `!builtins ? currentSystem || …` work instead of
  failing with `'builtins.currentSystem' is not available in pure evaluation mode`.

The zig dependencies (`zurl`, `ziggit`, and their own pins) are fetched from the projects' GitHub
mirrors and wired in as path dependencies: the upstream host `git.lilithsemi.com` serves nothing to
this machine, and a Nix build has no network (`packages/fix/patches/0002-*.patch` +
`packages/fix/vendor/*.zon`).

## Usage

```console
$ fix flake metadata /etc/nixos            # parses this repo's lock; cheap sanity check
$ fix eval --flake /etc/nixos#lastModified # evaluate a flake output
$ fix switch build --nixos --flake /etc/nixos#trantor --option substitute false
```

`fix switch build` evaluates the configuration and realizes the toplevel (no root, no activation),
which is the interesting path for rollout checks. Keep `--option substitute false` as everywhere
else in this repo. Realizing a changed closure can take a long time: with `substitute = false` the
daemon rebuilds everything from source (an LLVM update, for instance, is hours).

## Limits (upstream, not worked around)

- Pure `fix eval` of flake *inputs* that import relative files fails while the input still lives in
  fix's download cache instead of the store (upstream issue #43). Store-writing commands put inputs
  in the store and are unaffected.
- Ingest reads whole files with a 128 MiB cap; a *plain path* (`path:` ref or a non-git directory)
  containing such a file still errors. Git work trees are unaffected (only tracked files are
  ingested).
- `fix switch` activates through its own `sudo`, in place of `just agent-switch` / `nh os switch`.
  Use `fix switch build` for verification; keep the normal rollout path for activation.

## Package checks

```console
$ nix build .#fix --option substitute false          # the binary (completions + wrapped PATH)
$ nix build .#fix.tests.smoke --option substitute false   # eval + pure/impure gate smoke test
```
