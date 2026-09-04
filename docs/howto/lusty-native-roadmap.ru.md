# Lusty-native: дорожная карта (рендеринг, хоткеи, превью)

Согласованный план развития пикеров (standalone `lusty-native` + nvim float
`native.lua`/`native_pick`).

## Хоткеи

- Навигация: C-n/C-j/↓ вниз, C-p/C-k/↑ вверх, C-f/C-b/←/→ колонки, PgUp/PgDn страница, Home/End и
  C-a/C-e первый/последний.
- Запрос: C-u очистить, C-h/BS backspace, C-w очистить (файлы: затем вверх), C-k в prompt —
  kill-to-end (после перевода промпта в insert-режим).
- Действия: Enter/Tab открыть, C-t вкладка, C-o/C-v сплиты, C-d удалить буфер, C-s порядок
  сортировки, C-l цикл режима отображения, C-i иконки, C-Space/P превью, Esc/C-c/C-g закрыть.
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
- Сортировки: name|ext|size|time — standalone (CLI --sort) и float (C-s циклирует; serve
  пересортировывает листинг и между сменами возвращается к каноническому порядку depth+name).
  --reverse/--group-dirs-first — standalone (CLI).
- Иконки (nerd font) опционально (LUSTY_ICONS=1, standalone); tree-вид позже.
- Приоритет опций: CLI > env LUSTY\_\* > g:LustyExplorer\*.
- Примечание: long-формат общий для standalone и serve (listing::meta_line, маска 1 perm / 2 user /
  4 size / 8 time) — формат не дублируется.

## Превью (панель справа)

- Файл текст (head, подсветка), файл бинарь (MIME+hexdump), изображение (kitty protocol / degrade),
  каталог (мини-листинг), буфер (C-b), grep-hit (контекст вокруг), git-diff фрагмент, метаданные
  stat, recent (голова).
- Переключение C-Space/P; ширина LUSTY_PREVIEW_WIDTH; асинхронно, debounce, отмена устаревших;
  лимиты LUSTY_PREVIEW_MAX_BYTES; graceful degrade без изображений/nerd font.

## Порядок работ

- A: хоткеи, паритет standalone/float — готово.
- B: long-режим + сортировки — готово: standalone (CLI) и float (C-l long + serve M; C-s цикл
  name/ext/size/time).
- C: custom-колонки + env/config + иконки — готово (--columns/LUSTY_COLUMNS в standalone и float;
  g:LustyExplorerColumns читает float).
- D: превью текст/каталог/буфер/grep — по договорённости не делаем.
- E: изображения, git-diff, man — отложено (вместе с превью).
- F: тесты — serve M покрыт Rust-интеграционным тестом (tests/serve_m.rs); long/custom смоук float —
  ручной, headless-теста serve-пикера пока нет.
