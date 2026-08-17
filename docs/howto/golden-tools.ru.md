# Золотой набор CLI-инструментов (golden tool set)

Список быстрых современных замен стандартным утилитам, который обязаны использовать агенты
(dsh, Codex и т.п.) и желательно — человек в интерактивной оболочке на этой машине. Это
единственный источник правды: правила для агентов продублированы в `/etc/nixos/AGENTS.md`
(секция «Golden tool set»), а краткая версия для dsh лежит в скилле
`~/.dsh/skills/golden-tools/SKILL.md`.

## Зачем

Заменители быстрее и легче классических утилит по нескольким причинам:

- **Параллелизм и SIMD**: ripgrep/fd/fdupes-подобные обходят дерево в несколько потоков и
  используют SIMD-сканирование (memchr), тогда как `grep -r`/`find` однопоточные.
- **Уважение к `.gitignore`**: `rg`/`fd` по умолчанию пропускают `.git/`, `node_modules/` и всё,
  что перечислено в ignore-файлах — не нужно вручную писать `--exclude-dir`.
- **Меньше памяти и меньше мусора**: `rg` не грузит файлы целиком, `fd` не материализует дерево
  в памяти, `bat` читает только видимый диапазон строк.
- **Лучший вывод**: цвета, подсветка синтаксиса, человекочитаемые размеры, гит-статус в листинге.
- **Меньше токенов у агента**: один вызов `rg 'pattern' dir` с `--no-heading` даёт компактный
  вывод вместо многострочного `grep -rn --color=never`.

## Таблица замен

| Legacy (медленно/громоздко)      | Golden (быстро/удобно)      | Статус на хосте            | Где подключено в репо                                  |
| -------------------------------- | --------------------------- | -------------------------- | ------------------------------------------------------ |
| `grep -r`                        | `rg` (ripgrep)              | ✅ установлен              | `modules/cli/tools.nix`, `modules/user/nix-maid/cli/search.nix` |
| `grep -r` (интерактивно)         | `ugrep` / `ug`              | ✅ установлен              | `modules/cli/tools.nix` + `modules/cli/ugrep.nix` (`/etc/ugrep.conf`) |
| `find`                           | `fd`                        | ✅ установлен              | `modules/cli/tools.nix`, nix-maid `cli/search.nix`     |
| `cat`                            | `bat`                       | ✅ установлен, alias `cat` | nix-maid `cli/search.nix`, alias в `lib/aliae.nix`     |
| `ls`                             | `eza`                       | ✅ установлен, alias `ls`  | `modules/cli/tools.nix`, alias в `lib/aliae.nix`       |
| `diff`                           | `delta`                     | ✅ установлен (git-pager)  | `modules/cli/tools.nix`, nix-maid `cli/git.nix`        |
| `du`                             | `dust` / `ncdu`             | ✅ установлены             | `modules/cli/tools.nix`                                |
| `df`                             | `duf`                       | ✅ установлен              | `modules/cli/tools.nix` (`pkgs.neg.duf`)               |
| `top`                            | `btop`                      | ✅ установлен              | `modules/monitoring/pkgs/default.nix`, nix-maid `cli/monitoring.nix` |
| `ps`                             | `procs`                     | ⏳ добавляется (`pkgs.procs`) | `modules/cli/tools.nix`                            |
| `sed 's/a/b/'` (простая замена)  | `sd`                        | ⏳ добавляется (`pkgs.sd`) | `modules/cli/tools.nix`                                |
| `sed`/`awk` для JSON             | `jq`                        | ✅ установлен              | `modules/cli/file-ops.nix`, `modules/text/manipulate-packages.nix` |
| `cd` + запоминание пути          | `zoxide` (`z`)              | ✅ установлен              | `modules/cli/tools.nix`                                |
| интерактивный выбор              | `fzf`                       | ✅ установлен              | nix-maid `cli/search.nix` (+ `FZF_*` переменные)       |
| бенчмарк «на глаз»               | `hyperfine`                 | ✅ установлен              | `modules/dev/pkgs/default.nix`                         |
| `tree`                           | `erdtree` / `eza --tree`    | ✅ установлены             | `modules/cli/tools.nix`                                |

Легенда: ✅ — уже в системе; ⏳ — добавляется в `modules/cli/tools.nix`.

## Конфигурация (уже настроена)

- **rg**: `~/.config/ripgrep/ripgreprc` — `--no-heading --smart-case --follow --hidden` + исключения
  `.git/`, `node_modules/` и др. (nix-maid `cli/search.nix`). Для агентов `--no-heading` даёт
  компактные строки `path:line:match`.
- **bat**: `~/.config/bat/config` — тема `ansi`, без пагинации и рамок (удобно в пайпах).
- **fzf**: `FZF_DEFAULT_COMMAND` уже построен на `fd` (`fd --type=f --hidden --exclude=.git`);
  превью файлов через `bat`, директорий через `eza --tree`.
- **git**: pager = `delta` (nix-maid `cli/git.nix`), плюс `diff-so-fancy` для форматирования.
- **ugrep**: системный `/etc/ugrep.conf` (цвета, `hidden`, `no-pager` и т.д.) — `modules/cli/ugrep.nix`.
- **алиасы оболочки**: `ls`→`eza`, `cat`→`bat` (cross-shell через aliae, `lib/aliae.nix`);
  nix-алиасы в `environment.shellAliases` (`modules/cli/tools.nix`).

## Примеры для агентов

Поиск по коду (компактно, с учётом .gitignore):

```bash
rg 'pattern' /path/to/dir            # файлы+номера строк, по умолчанию рекурсивно
rg -l 'pattern' .                    # только имена файлов
rg -t nix 'mkIf' modules/            # только .nix
rg --pcre2 '(?<=foo)bar' .           # PCRE lookbehind (rg -r — это ЗАМЕНА, не рекурсия!)
```

Поиск файлов:

```bash
fd '\.nix$' modules/                 # вместо find modules/ -name '*.nix'
fd -e md -x wc -l {}                 # выполнить команду для каждого результата
fd -t d 'venv'                       # только директории
```

Чтение и обработка:

```bash
bat --line-range :50 file.nix        # первые 50 строк с подсветкой
jq -r '.[].name' flake.lock          # вместо sed/awk по JSON
sd 'old' 'new' file.txt              # простая замена; sd -s — литеральная, без regex
procs --tree                         # дерево процессов вместо ps -ef
```

Замер скорости (когда нужно доказать, что замена быстрее):

```bash
hyperfine 'grep -r foo .' 'rg foo .' # сравнение legacy vs golden
```

## Когда замены НЕ использовать

- **Скрипты, которые должны работать не только здесь**: на удалённых/не-NixOS хостах `rg`/`fd`
  может не быть — пишите переносимо (POSIX `grep`/`find`) или явно проверяйте наличие.
- **POSIX-контексты**: `grep -o`/`-c`/`-B/-A` в rg есть, но тонкие отличия семантики (например
  `rg -r` = replace) — при переносе проверяйте флаги.
- **PCRE-специфика**: rg по умолчанию Rust-regex (без lookbehind); нужен `--pcre2`.
- **Двоичные файлы / архивы**: классический `grep -a`/`zgrep` иногда удобнее; для этого и стоит
  `ugrep` (умеет в архивные/бинарные). Редкие экзотические флаги `grep` (например `-P` в старых
  версиях) не имеют эквивалента — тогда оставайтесь на `grep`.
- **Интерактивные пейджеры и TTY**: `bat` в пайпе без `--paging=never`/`-p` может вести себя как
  пейджер; для агентов всегда добавляйте `-p` или `--paging=never`.

## Как устроен «золотой набор» в этом репо

| Слой                          | Что содержит                                                        | Где                                                     |
| ----------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------- |
| Правила для агентов (я/мы)    | жёсткие правила выбора инструментов, загружаются в каждую сессию    | `AGENTS.md` (секция «Golden tool set»)                  |
| Справочник                    | эта страница                                                        | `docs/howto/golden-tools.ru.md`                         |
| Скилл для dsh                 | краткая версия правил, видна в каталоге скиллов dsh                 | `~/.dsh/skills/golden-tools/SKILL.md`                   |
| Пакеты и конфиги              | установка инструментов, алиасы, конфиги rg/bat/fzf/git/ugrep        | `modules/cli/tools.nix`, `modules/cli/ugrep.nix`, nix-maid `cli/search.nix`, `cli/git.nix`, `lib/aliae.nix` |

Проверка установки: `command -v rg fd bat eza delta jq zoxide duf dust ncdu btop procs sd hyperfine`.

Изменения в пакетах требуют пересборки системы (`nh os switch /etc/nixos#odin --option substitute false`);
изменения в `~/.dsh/skills/` подхватываются новой сессией dsh без пересборки.
