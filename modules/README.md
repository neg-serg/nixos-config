## Modules layout

All system modules now follow a consistent pattern:
- Each domain folder has a `modules.nix` that imports its submodules.
- `default.nix` in the domain simply imports `./modules.nix`.
- Host profiles (see `profiles/`) compose domains instead of importing individual files.

Primary domains:
- `cli`, `dev`, `media`, `hardware`, `system`, `user`, `servers`, `monitoring`, `security`, `roles`, `nix`, `tools`, `documentation`, `appimage`, `llm`, `flatpak`, `games`, `finance`, `fun`, `text`, `db`, `torrent`, `fonts`, `web`, `emulators`.

Legacy/top-level files:
- `args.nix`, `features.nix`, `neg.nix` remain as shared wiring.
- `home-manager/` contains HM glue and still lives here for now.

When adding a new module in a domain, include it in that domain’s `modules.nix` rather than editing `default.nix`. Keep domain-specific READMEs close to their folders if needed.***
