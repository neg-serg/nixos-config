## Modules Layout / Структура модулей

All system modules now follow a consistent pattern:

Все системные модули следуют единому паттерну:

- Each domain folder has a `modules.nix` that imports its submodules.

- `default.nix` in the domain simply imports `./modules.nix`.

- Host profiles (see `profiles/`) compose domains instead of importing individual files.

- Каждая папка домена имеет `modules.nix`, который импортирует подмодули.

- `default.nix` в домене просто импортирует `./modules.nix`.

- Профили хостов (см. `profiles/`) компонуют домены вместо импорта отдельных файлов.

## Primary Domains / Основные домены

`cli`, `dev`, `media`, `hardware`, `system`, `user`, `servers`, `monitoring`, `security`, `roles`,
`nix`, `tools`, `documentation`, `appimage`, `llm`, `flatpak`, `games`, `finance`, `fun`, `text`,
`db`, `torrent`, `fonts`, `web`, `emulators`.

## Legacy Files / Устаревшие файлы

- `args.nix`, `features.nix`, `neg.nix` remain as shared wiring / остаются как общая проводка.

## Adding Modules / Добавление модулей

When adding a new module in a domain, include it in that domain's `modules.nix` rather than editing
`default.nix`.

При добавлении нового модуля в домен, добавляйте его в `modules.nix` этого домена, а не редактируйте
`default.nix`.
