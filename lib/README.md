# Lib

Custom Nix library files, imported via `specialArgs.opts` / `lib/opts.nix` and direct imports.

## Files

- `opts.nix` — option helpers (`mkOpt`, `mkBoolOpt`, `mkStrOpt`, …); consumed via `opts` specialArg
  (see `flake/nixos.nix`) and directly by modules.
- `neg-helpers.nix` — structural helpers: the home-file helper (`mkHomeFiles`), `importDir`
  (directory auto-import for every module aggregator, with `nameFilter` for dropping entries by
  name) and the by-name resolver `tree` / `leaves` / `find`; `systemdUser` closes `systemd-user.nix`
  over a given `lib`. Single source for `specialArgs.neg` (flake/nixos.nix) and `flake/checks.nix`;
  also re-exports `ruKeys` from `ru-keys.nix`.
- `systemd-user.nix` — systemd unit helpers: `mkUnitFromPresets` plus the module-shaped
  `mkUserService` / `mkUserOneshot` / `mkUserActivation`, and the system-level oneshot+timer factory
  `mkOneshotTimer` used by `hosts/odin`; the legacy `mkSimple*` helpers were removed. The `presets`
  table holds both scheduling keys (`after`/`wants`/`requires`/`bindsTo`/`partOf`/`wantedBy`) and a
  `service` attrset (`Restart`/`RestartSec`/`Type`): `defaultWanted`, `restartOnFailure`, `oneshot`,
  `graphicalSession`, `graphicalWanted`. Preset service keys are merged under the caller's own
  `serviceConfig` (caller wins per key), so `presets = [ "restartOnFailure" ]` + `RestartSec = 3`
  keeps the shared policy while tuning the delay; a raw `Restart = "on-failure"` inside
  `systemd.user.services` is rejected by the `restart-preset` rule in `scripts/dev/lint-guards.sh`.
- `llama-server.nix` — `mkService { description, execStart, user }`, the systemd unit skeleton
  shared by `modules/llm/llama-server.nix` and `llama-server-flash-next.nix` (manual-start-only
  policy, `render`/`video` groups); exposed as `config.lib.neg.llamaServer` like `systemdUser`.
- `aliae.nix` — shell alias definitions (`alias`-style helpers for the user's shell); imports
  `package-checks.nix` to skip aliases whose packages are missing.
- `package-checks.nix` — package availability checks (`hasRg`, `hasNmap`, `hasCurl`, …) for the
  alias generators.
- `fzf-opts-tests.nix` — eval-only assertions over `neg-helpers.nix`'s `hasFzfHashComment`; wired
  into `flake/checks.nix` as the `fzf-opts-guard` check.
- `ru-keys.nix` — single source of truth for the RU-layout hotkey problem: latin key → the char the
  ru layout produces, and every per-app duplicate bind is generated from this table. Exposed as
  `neg.ruKeys`; mechanics in `docs/howto/hotkeys-ru-layout.md`.
- `neg-helpers-tests.nix` — eval-only assertions over `tree` / `leaves` / `find` and `importDir`'s
  `nameFilter` (extension stripping, `default.nix` addressing its own directory, `_`-prefixed
  entries being skipped, a miss aborting evaluation); wired into `flake/checks.nix` as
  `neg-tree-guard`.
- `ru-keys-tests.nix` — eval-only assertions over `ru-keys.nix` (neovim langmap golden, table
  parity); wired into `flake/checks.nix` as the `ru-keys` check.
- `feature-flags-tests.nix` — scans `modules/` + `hosts/` for `lib.neg.enabled "<path>"` and asserts
  every path resolves to a declared `features.<path>.enable` option (a typo or a missing `.enable`
  silently reads false); wired into `flake/checks.nix` as the `feature-flags` check against the
  feature option tree evaluated with `modules/core` + `modules/features`.
- `caches.nix` — shared binary-cache `trusted-public-keys` (official cache plus community mirrors);
  imported by `modules/nix/settings.nix`.
- `python-packages.nix` — shared Python package list; single source for the system Python env
  (`modules/dev/python/pkgs.nix`) and the Python devshell (`flake/devshells/python.nix`).
- `quickshell-wrapper.nix` — Quickshell wrapper helpers (used by
  `modules/user/nix-maid/gui/quickshell.nix`).
- `quickshell-wrapper-install.sh` — install-phase template read by `quickshell-wrapper.nix`
  (`builtins.readFile`); builds the wrapped `qs` binary with the Qt/QML import paths, theme data and
  `QT_QPA_PLATFORM=wayland`.

Runtime helpers (`mkHomeFiles`, `path`, `pathExists`, `enabled`, …) live on `config.lib.neg`
(defined in `flake/nixos.nix` specialArgs + exposed via `modules/core/neg.nix`), not under `lib/`.

## Repo-root file references

To reference a file by its repo-root-relative path instead of fragile `../../../` chains, use
`config.lib.neg.path` in any module:

```nix
{ config, ... }:
{
  environment.etc."foo/bar".source = config.lib.neg.path "files/foo/bar";
}
```

- `path "files/gui/vicinae-theme.toml"` → a real path to that file (resolved against
  `options.neg.repoRoot`, a path literal injected via specialArgs from `flake/nixos.nix`). Because
  the result is a path (not a string), Nix copies the file into the store and tracks it as a closure
  dependency — the same behavior as the old relative `./../../` references. Do not replace `path`
  with a plain string: strings are not added to derivation closures and their files can be
  garbage-collected.
- `pathExists "…"` — like `builtins.pathExists`, but repo-root-relative (no error when missing); use
  it for optional files.
- Use `path` for **repo-root** targets only (`files/`, `secrets/`, `lib/`, `packages/…`). Sibling
  imports within one area (e.g. `../scripts/`) stay relative.
- Derivation `src` in `mkDerivation` must remain a real path (string breaks input tracking); keep
  `src = ./relative/…` there.

### By name, not by path

`neg.tree` + `neg.find` take the counting out of references: a directory is exposed as an attribute
set keyed by short names, so a file is addressed by its name alone.

```nix
{ config, neg, ... }:
let
  libTree = neg.tree { dir = config.lib.neg.path "lib"; };
in
{
  systemdUser = import (neg.find libTree "systemd-user") { inherit lib; };
}
```

Conventions, identical for every tree (borrowed from import-tree / haumea):

- a directory recurses and its `default.nix` shows up as that directory's `.default` (not as the
  whole value, so sibling modules stay reachable next to it);
- entries starting with `_` or `.` are skipped (private data, hidden files);
- the matching extension is stripped from the key (`systemd-user.nix` → `systemd-user`), so `find`
  accepts the name with or without `.nix`. Nothing is camel-cased: a non-`.nix` file keeps its
  dashes, so address it as `t."hdr-auto-switch"` (that is what makes the mapping predictable);
- `find` throws on a missing or ambiguous name and prints the candidates, so a mistake is a one-line
  fix instead of a grep.

`importDir` gained `nameFilter` for the same purpose: `modules/default.nix` drops whole domains by
name and no longer lists a single path.

```nix
imports = neg.importDir { dir = ./.; includeDirs = true; nameFilter = domainFilter; };
```

### Which resolver, where

| Where the reference sits                       | Use                                                                                                                                    | Why                                                                                                                                                                      |
| ---------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| a config body (option value, `config = …`)     | `config.lib.neg.path` / `readFile` / `files.<…>`                                                                                       | `config` is already the module's own argument                                                                                                                            |
| a top-level `let` of a module                  | `let r = neg.rooted repoRoot; in r.path "files/x"`                                                                                     | `config.lib.neg.*` there is an **infinite recursion**: module arguments are forced while the module is being collected (`hosts/odin/services/telegram-units.nix` hit it) |
| a package file (`packages/<name>/default.nix`) | `paths.path "files/…"` — declare `paths` as a formal and `neg.functions.callPkg` fills it in (it sniffs formals exactly like `inputs`) | no `config` at all; the resolver is built once in `packages/overlay.nix` (`neg.rooted ../.`) and handed to every overlay through `importOvP`                             |
| a package referring to a *sibling* package     | `call (pkg "name") { }` — `neg.functions.pkg` maps the directory name to its `default.nix`                                             | no path arithmetic anywhere in `packages/`, and a typo lists the names that exist instead of pointing at a missing file                                                  |

`config.lib.neg.files` is the whole `files/` directory as one attribute set (built lazily,
`extensions = "any"`, so keys drop their extension and colliding names keep the full one), for
references whose target is data rather than a path string.

From the shell, `paths` (a `~/.local/bin` tool, wrapped as `just paths`) answers the same questions:
`paths keys files` prints what to write for `files/…`, `paths keys modules --any` does the same for
the module tree, `paths refs systemd-user` shows every reference to a name, `paths find wl-monitor`
picks a file with fzf and lists who uses it, and
`paths resolve ../../../lib/x.nix --from hosts/odin/services/y.nix` resolves a relative reference
(and warns when it leaves the repo).

The rule is enforced: `scripts/dev/check-relative-paths.sh` (run by `just lint` and as the
`relative-paths-guard` flake check) fails on **any** `../` in `modules/`, `hosts/` and `packages/` —
the three trees are at zero. A line that truly must go up carries `# allow-relative: <reason>` on
itself or the line before it; a file whose `../` all belong to something embedded (a build script
walking the unpacked source tree) carries `# allow-relative-file: <reason>` and is listed by the
guard, so the exemption stays visible.
