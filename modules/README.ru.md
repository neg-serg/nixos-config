## Структура модулей

Все системные модули следуют единому паттерну:

- Каждая папка домена имеет `modules.nix`, который импортирует подмодули.

- `default.nix` в домене просто импортирует `./modules.nix`.

- Профили хостов (см. `profiles/`) компонуют домены вместо импорта отдельных файлов.

## Основные домены

`cli`, `dev`, `media`, `hardware`, `system`, `user`, `servers`, `monitoring`, `security`, `roles`,
`nix`, `tools`, `documentation`, `appimage`, `llm`, `flatpak`, `games`, `finance`, `fun`, `text`,
`db`, `torrent`, `fonts`, `web`, `emulators`.

## Устаревшие файлы

- `args.nix`, `features.nix`, `neg.nix` остаются как общая проводка.

## Добавление модулей

При добавлении нового модуля в домен, добавляйте его в `modules.nix` этого домена, а не редактируйте
`default.nix`.
