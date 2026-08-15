# Documentation

- Manuals (canonical workflows): [manual/README.md](./manual/README.md)
- How-tos and reference (focused guides, pinning notes, hotkeys): [howto/index.md](./howto/index.md)
- Runbooks and scripts (operational steps, credentials, maintenance helpers):
  [runbooks/index.md](./runbooks/index.md)

## Structure / Options Docs — which doc to read

| Doc                                       | Role                                                                                           | Source                          |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------- | ------------------------------- |
| [codebase.md](./codebase.md)              | Structural map: layout, hosts, module domains, feature flags with defaults, packages, overlays | generated — `just codebase`     |
| [modules.md](./howto/modules.md)          | Full option reference: every option with type/default/description                              | generated — `just docs-modules` |
| [OPTIONS.md](../OPTIONS.md)               | Human-curated feature overview: profiles, unfree, exclusions, notable behaviors                | manual (repo root)              |
| [modules/README.md](../modules/README.md) | Module tree conventions: domains, auto-import, how to add a module                             | manual                          |

Rule of thumb: for any `features.*` flag's default/type → `codebase.md` or `modules.md` (generated,
always fresh); for *why* flags compose the way they do → `OPTIONS.md`; for *where things live and
how to add* → `modules/README.md`.

## Repo Map

- [codebase.md](./codebase.md) — generated structural map (modules, features, profiles, packages);
  regenerate with `just codebase`
