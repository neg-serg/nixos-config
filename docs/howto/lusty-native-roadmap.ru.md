# Lusty-native: дорожная карта (рендеринг, хоткеи, превью)

Согласованный план развития пикеров (standalone `lusty-native` + nvim float
`native.lua`/`native_pick`).

## Хоткеи

- Навигация: C-n/C-j/↓ вниз, C-p/C-k/↑ вверх, C-f/C-b/←/→ колонки, PgUp/PgDn страница, Home/End и
  C-a/C-e первый/последний.
- Запрос: C-u очистить, C-h/BS backspace, C-w очистить (файлы: затем вверх).
- Действия: Enter/Tab открыть, C-t вкладка, C-o/C-v сплиты, C-d удалить буфер, C-y порядок
  сортировки (C-s не вешаем: XOFF/kitty-конфликт), C-l цикл режима отображения, C-Space/P превью,
  Esc/C-c/C-g закрыть.
- Ограничения: h/j/k/l не трогаем (буквы фильтра); C-s не вешаем в standalone (terminal suspend);
  паритет standalone/float.

## Режимы отображения (eza-подход)

- Источник: метаданные только по видимым строкам (serve: запрос M по индексу; standalone:
  fs::metadata лениво). Кэш листинга не зависит от режима.
- grid — row-major (имя+цвет).
- long — строка на файл: perms uid size time name (как eza -l), human-readable размер. Standalone и
  nvim-float: C-l переключает; в float метаданные приходят запросом serve M только для видимых строк
  и форматируются тем же кодом, что и standalone (listing::meta_line).
- custom — выбор подмножества полей perm,user,size,time (имя всегда последним); конфиг
  g:LustyExplorerColumns / LUSTY_COLUMNS / --columns.
- Сортировки: name|ext|size|time — standalone (CLI --sort) и float (C-y циклирует; serve
  пересортировывает листинг и между сменами возвращается к каноническому порядку depth+name).
  --reverse/--group-dirs-first — standalone (CLI) и float (g:LustyExplorerDirsFirst /
  g:LustyExplorerReverse или env LUSTY_DIRS_FIRST / LUSTY_REVERSE; как и в standalone, действуют
  только на канонический порядок по имени).
- Иконки (nerd font) опционально: standalone — LUSTY_ICONS=1; float — g:LustyExplorerIcons=1 (или
  LUSTY_ICONS=1); tree-вид позже.
- Приоритет опций: CLI > env LUSTY\_\* > g:LustyExplorer\*.
- Примечание: long-формат общий для standalone и serve (listing::meta_line, маска 1 perm / 2 user /
  4 size / 8 time) — формат не дублируется.

## Превью (панель справа)

- Сделано в standalone (C-Space/Shift+P; ширина LUSTY_PREVIEW_WIDTH, лимит LUSTY_PREVIEW_MAX_BYTES):
  изображения (chafa ANSI-art — работает в любом терминале; нативный kitty-протокол — следующий
  шаг), git-diff выбранного файла (unstaged), man-страницы (.1..9/.man/.gz через man -l).
- Не делаем: файл-текст/бинарь/каталог/буфер/grep/stat/recent (пункт D).
- Асинхронный рендер/отмена устаревших — не делаем (рендер по смене выделения с кэшем).

## Порядок работ

- A: хоткеи, паритет standalone/float — готово.
- B: long-режим + сортировки — готово: standalone (CLI) и float (C-l long + serve M; C-y цикл
  name/ext/size/time).
- C: custom-колонки + env/config + иконки — готово (--columns/LUSTY_COLUMNS в standalone и float;
  g:LustyExplorerColumns читает float; иконки в float — g:LustyExplorerIcons=1 / LUSTY_ICONS=1).
- D: превью текст/каталог/буфер/grep — по договорённости не делаем.
- E: изображения, git-diff, man — готово в standalone (chafa/git diff/man; C-Space/Shift+P);
  kitty-протокол для изображений — следующий шаг.
- F: тесты — serve M покрыт Rust-интеграционным тестом (tests/serve_m.rs); headless-смоуки float:
  smoke.lua, native_float_smoke.lua, filesystem_float_smoke.lua, filesystem_float_icons_smoke.lua
  (check-lusty-smoke.sh).
