# LustyExplorer: Lua-порт для современного Neovim

Порт классического плагина [sjbach/lusty](https://github.com/sjbach/lusty) (LustyExplorer, VimL +
Ruby) на Lua под конфиг `files/nvim`. Оригинал в Neovim не работал — в нём нет интерфейса `if_ruby`.

Код живёт в `files/nvim/lua/lusty/` и подключается из `files/nvim/init.lua` на событии `VeryLazy`
(`require'lusty'`).

## Команды и клавиши

| Команда                            | Клавиша                    | Действие                                                                      |
| ---------------------------------- | -------------------------- | ----------------------------------------------------------------------------- |
| `:LustyFilesystemExplorer [путь]`  | `<Leader>lf`               | файловый explorer (cwd, либо указанный путь)                                  |
| `:LustyFilesystemExplorerFromHere` | `<Leader>l` / `<Leader>lr` | файловый explorer из каталога текущего файла (одинарный `,l` — быстрый вызов) |
| `:LustyBufferExplorer`             | `<Leader>lb`               | explorer буферов (MRU + fuzzy)                                                |
| `:LustyBufferGrep`                 | `<Leader>lg`               | regex-поиск по всем загруженным буферам                                       |

Старые имена `:BufferExplorer`, `:FilesystemExplorer`, `:FilesystemExplorerFromHere` оставлены как
заглушки с предупреждением (как в оригинале).

## Поведение

- Explorer открывается во **floating-окне** (rounded border, по центру экрана), а не в split — он не
  трогает раскладку окон и не может «схлопнуть» соседние окна в микроскопические. В последней строке
  окна — prompt `>>`.
- Набор текста фильтрует записи fuzzy-алгоритмом Mercury (портирован 1:1).
- Раскладка: dual-mapping в стиле langmapper — под русской йцукен-раскладкой физические клавиши
  работают как EN (клавиша `.` шлёт `ю` → печатается `.` и показываются скрытые; `и` → `b` и т.д.),
  переключать раскладку не нужно.
- `<Enter>`/`<Tab>` — открыть выбранное; `<C-t>` — в новой вкладке; `<C-o>`/`<C-v>` — в
  горизонтальном/вертикальном сплите.
- `<C-n>`/`<C-p>` — следующий/предыдущий; `<C-f>`/`<C-b>` — по колонкам; `<C-u>` — очистить prompt;
  `<Esc>`/`<C-c>`/`<C-g>` — отмена (просто закрывает окно и возвращает фокус, без переключения
  буферов и без `E37`-ошибок даже при `'hidden' off`).
- Буферы упорядочены по MRU (текущий — последним, выделен подсветкой); при пустом запросе — чистый
  MRU, при запросе — сначала по score Mercury, при равенстве — по номеру буфера.
- Файловый explorer: мемоизация каталогов (`<C-r>` — refresh), переход по `dir/` и `../`, `~` и
  `$VAR` в prompt, dotfiles скрыты, пока запрос не начинается с `.` (или
  `g:LustyExplorerAlwaysShowDotFiles = 1`), маски из `&wildignore` (или устаревший
  `g:LustyExplorerFileMasks`).
- Цвет как в `ls --color`: палитра берётся **строго из `LS_COLORS`, унаследованного от shell** (у
  тебя: `~/.config/dircolors/dircolors` → `dircolors -b` в zsh), без каких-либо собственных правил
  поверх. Если `LS_COLORS` в окружении нет — используется дефолт `dircolors -b` (то же, что у plain
  `ls --color`). Типы `di`/`ln`/`ex`/`so`/`pi`..., затем правила `*.ext`. То же применяется к именам
  буферов в BufferExplorer (по расширению файла).
- Размеры float: ширина ~90% экрана, высота подстраивается под контент (таблица целиком + строка
  prompt), максимум ~80% высоты экрана; минимум строк — одна на запись (при малом числе). Gravity по
  умолчанию `center` (настраивается, см. опции). Нижняя строка — prompt `>>`, без подсказок. В
  файловом explorer путь в промпте показывается как в shell-промпте: `$HOME` сокращается до `~`,
  тильда/разделители/текст пути красятся цветами из `neg.omp.json` (`#287373`/`#005faf`/`#95a7bc`).
- `<C-d>` в буферном explorer — выгрузить выбранный буфер.
- `<C-a>`/`<Shift-Enter>` в файловом — открыть все файлы из текущего вида; `<C-e>` — создать новый
  файл по тексту prompt.

## Опции

- `g:LustyExplorerDefaultMappings` (по умолчанию 1) — `0` отключает `<Leader>lf/lr/lb/lg`.
- `g:LustyExplorerAlwaysShowDotFiles` — показывать dotfiles всегда.
- `g:LustyExplorerFileMasks` — устаревший аналог `&wildignore`.
- `g:LustyExplorerShowColors` (по умолчанию включено) — `0` отключает dircolors-раскраску ячеек.
- `g:LustyExplorerWidthRatio` (0.9) — доля ширины экрана под float (0.4–1.0).
- `g:LustyExplorerMaxHeightRatio` (0.8) — максимум высоты float в долях экрана (0.3–0.95).
- `g:LustyExplorerGravity` (`center`) — позиция float по вертикали: `top`, `center` или `bottom`.

## Изменения в конфиге

- Убран `{ '<leader>l', ... }` (файлы в текущем каталоге) из `files/nvim/lua/plugins/ui/snacks.lua`
  — комбинация `gz` делает то же самое, а префикс `<Leader>l` освобождён под Lusty (`lf/lr/lb/lg`).

## Ограничения

- LustyJuggler (бар MRU-буферов) не портирован — не был заказан.
- BufferGrep переводит Ruby-подобный regex в Vim-паттерн (обычный 'magic'): поддерживаются `(a|b)`,
  `+`, `?`, `{m,n}`, `\b`, `\d`, `\w`, `\s`; поиск всегда без учёта регистра. Сложные конструкции
  (lookahead и т.п.) не поддержаны.
- Файлы по `scp://` показываются (через `ssh ls`), но открытие требует netrw, который в конфиге
  отключён.

## Проверка

Headless-тесты (nvim): `nvim --clean --headless -l files/nvim/lua/lusty/tests/smoke.lua` —
открытие/фильтр/навигация/рекурсия файлового explorer, dircolors-раскраска, MRU-порядок буферов,
C-d, hits BufferGrep (включая `\b`-границы).

Изменения вступают в силу после пересборки конфига:
`nh os switch /etc/nixos#odin --option substitute false`.
