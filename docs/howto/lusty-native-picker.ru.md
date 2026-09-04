# Lusty-native: отдельный пикер на Rust (архитектура)

## Цель

Заменить медленные части LustyExplorer (Lua-порт в nvim) на отдельный нативный процесс, сохранив
nvim как редактор. Целевой выигрыш — в 10 и более раз на наборе текста и на листинге больших
каталогов.

Замеры (headless, репо-копия, /etc/nixos):

| Операция                                  | Сейчас (Lua)           | Цель (Rust)                        |
| ----------------------------------------- | ---------------------- | ---------------------------------- |
| list /home/neg, depth 1 (11 записей)      | 4.9 ms                 | < 1 ms                             |
| list /etc/nixos, depth 2 (271 запись)     | 8.0 ms                 | < 2 ms                             |
| list /nix/store, depth 1 (151 363 записи) | **4884 ms**            | < 150 ms                           |
| fuzzy.score × 5000                        | 1.2 ms                 | < 0.5 ms                           |
| набор текста (латентность)                | перерисовка float nvim | нативный ratatui, частичный redraw |

Два бутылочных горлышка в текущем Lua-порте:

1. **B1 — перерисовка float-окна nvim** на каждую клавишу (это «набор тормозит» на обычных
   каталогах; логика тут 0.1–0.2 ms на callback).
1. **B2 — синхронный листинг** `vim.fn.readdir` + по одному `vim.fn.getftype` (stat) на файл, в
   UI-потоке: 151k файлов = 4.9 с. Нативный `fd` делает те же 151k за ~107 ms и асинхронно.

## Модель процесса (Model 1, в стиле fzf)

- nvim-обёртка (`,l`/`,C`/`,B`/`,G`) открывает терминал через `termopen` и запускает
  `lusty-native <mode> <root>`.
- Бинарь рисует на альтернативном экране (ratatui/crossterm), пользователь набирает/выбирает, по
  выбору бинарь печатает в stdout строку `ACTION<TAB>PATH` и выходит с кодом 0; отмена — код 1.
- `on_exit` в Lua читает stdout и открывает файл в nvim (edit/tab/split), переиспользуя текущую
  логику открытия буферов. RPC-демон не нужен.
- Позже опционально: постоянный процесс + msgpack-RPC через `nvim --listen`.

## Компоненты

1. `packages/lusty-native` — Rust-крэйт (двоичный `lusty-native`):

   - `cli`: mode (files|buffers|grep), root, depth, skip-dirs, follow-mounts, dotfile-флаг,
     стартовый query.
   - `listing`: `ignore`/`walkdir` + `rayon` (параллельный обход), ограничение глубины, пропуск
     точек монтирования (/proc/self/mountinfo), skip-dirs glob (`~`/`*`/`?`), порядок «менее
     вложенные сверху».
   - `scoring`: порт `fuzzy.lua` (fzy-стиль) на Rust + префикс-якорь первой буквы (первая буква
     запроса = префикс имени). Mercury — опционально.
   - `colors`: парсинг LS_COLORS (env → файл dircolors → `dircolors -b`), ANSI-раскраска
     dir/symlink/ext; приоритет как сейчас в `ls_colors.lua`.
   - `ui`: ratatui — строка запроса, список с инкрементальным частичным redraw, гравитация (по
     умолчанию снизу), выделение, RU-раскладка (dual-mapping физических клавиш в EN), тот же набор
     клавиш.
   - `output`: на Enter/Tab/C-t/C-o/C-v печатает `ACTION<TAB>PATH`.

1. `files/nvim/lua/lusty/native.lua` — шим: `termopen` + `on_exit` + передача опций. Старый Lua-порт
   остаётся фолбэком (`g:LustyExplorerNative=0`).

## Паритет UX (обязательно сохранить)

- Клавиши: Enter/Tab, C-t, C-o/C-v, C-n/C-p, C-f/C-b (колонки), C-l (long-режим с метаданными), C-u
  (очистить), Esc/C-c/C-g (отмена), C-w (вверх по каталогу), точка (показать скрытые), RU-раскладка
  без переключения.
- Глубина по умолчанию 2, skip-dirs `pic,tmp`, пропуск точек монтирования, «менее вложенные сверху»,
  glob-скип `~`/`*`/`?`, префикс-якорь.
- Только dircolors/LS_COLORS; путь в prompt раскрашен как в zsh/oh-my-posh.
- Буферы: MRU-порядок (текущий последним) + fuzzy; grep: hits + `\b`-границы.

## Фазы

1. Каркас крэйта + nix-пакет (паттерн `hypr-focus`) + `--list <dir>` с листингом (depth/skip/mount).
   Бенч против Lua.
1. Порт скоринга + фильтр по запросу + префикс-якорь (юнит-тесты из smoke).
1. LS_COLORS + ANSI-вывод.
1. ratatui UI + клавиши + RU-раскладка + гравитация.
1. nvim-шим: termopen + on_exit + опции; подключить `,l`/`,C`/`,B`/`,G`; регрессия.
1. Режимы buffers + grep.
1. Бенч + документация + фолбэк Lua.

## Nix-упаковка

- `packages/lusty-native/default.nix` = `rustPlatform.buildRustPackage` (src `./.`, свой
  `Cargo.lock`), `meta.mainProgram = "lusty-native"`.
- Wire в `packages/overlays/tools.nix` через `callPkg (packagesRoot + "/lusty-native") { }`; станет
  `pkgs.neg.lusty-native`.
- Добавить в home-пакеты (`modules/user/nix-maid/...`) рядом с nvim-конфигом.
