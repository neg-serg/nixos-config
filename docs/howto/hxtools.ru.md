# hxtools: что поставить и как пользоваться

`pkgs.neg.hxtools` подключается ролью мониторинга или опциональным набором dev/pkgs.misc. Для
разового использования из репозитория: `nix shell .#hxtools -c <команда>` (или
`nix shell nixpkgs#hxtools` вне флейка).

## Git и статистика

| Команда | Назначение | Пример | | --- | --- | --- | | `git forest [--all --style=10 --sha]` |
Консольный граф коммитов с древовидными линиями. | `git forest --all --style=10 --sha | less -RS` |
| `git-blame-stats [rev] [paths...]` | Подсчёт строк по авторам через `git blame`; полезно для «чья
эта зона». | `git-blame-stats HEAD src/` | | `git-author-stat [range]` | Топ авторов по количеству
коммитов в диапазоне. | `git-author-stat v1.0..v1.1` | | `git-revert-stats [range]` | Кто чаще всего
делает revert в диапазоне. | `git-revert-stats origin/main~200..` | | `git-track remote/branch` |
Настроить tracking для текущей ветки. | `git-track origin/main` |

`git forest` понимает `--svdepth=N` для более плотных суб-веток и выводит SHA (`--sha`), если нужно
копировать ссылки на коммиты.

## Мониторинг и администрирование

| Команда | Назначение | Пример | | --- | --- | --- | | `hxnetload <iface> [interval]` |
Онлайн-просмотр Rx/Tx в КБ/с из `/proc/net/dev`; интервал можно задать в секундах или, если >50000,
в микросекундах. | `hxnetload wlan0 1` | | `sysinfo [-v]` | Краткая строка с ОС, ядром, CPU, памятью
и дисками — удобно кидать в чат/тикет. | `sysinfo` | | `tailhex [-f] [-B bytes] <file>` | Hex-dump c
продолжением как у `tail -f`; удобно смотреть бинарные логи. | `tailhex -f /var/log/wtmp` | |
`wktimer -A/-S/-L <name>` | Таймеры для учёта работы: создать, остановить, вывести таблицу
(`~/.timers`). | `wktimer -A task && wktimer -S task && wktimer -L` |

## Текст, архивы и медиа

| Команда | Назначение | Пример | | --- | --- | --- | | `pegrep <perl-regex> files...` | Глобальный
поиск по Perl-совместимому паттерну с мультирядной поддержкой. |
`pegrep '}\s*else' $(find src -name '*.cpp')` | | `pesubst -s <src> -d <dst> [-m mods] files...` |
Подстановка по Perl-regex по всему файлу (аналоги `sed -e 's///g'`). |
`pesubst -s foo -d bar -ms config.yaml` | | `qtar [-x] [--ext|--svn] <archive> <paths...>` | Создать
tar с сортировкой по расширениям/базовым именам; `-x` исключает .git/.svn и др. |
`qtar -x --ext backup.tar.gz src docs` | |
`qplay [-i part] [-q part] [-r rate] [files...] | aplay -f dat -c 1` | Преобразовать PLAY-строки
QBASIC в PCM и отправить на `aplay`; по умолчанию смешивает square+sin. |
`echo "L16O2CDEFGAB>L4C" | qplay - | aplay -f dat -c 1` |

Остальные утилиты смотрите в `man hxtools` — там перечислены все `hx*`, включая редкие штуки вроде
`tailhex`, `peicon`, `mailsplit` и инструментов для гейм-архивов.
