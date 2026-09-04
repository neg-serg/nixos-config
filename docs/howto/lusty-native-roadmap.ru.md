# Lusty-native: дорожная карта (рендеринг, хоткеи, превью)

Согласованный план развития пикеров (standalone `lusty-native` + nvim float
`native.lua`/`native_pick`).

## Хоткеи

- Навигация: C-n/C-j/↓ вниз, C-p/C-k/↑ вверх, C-f/C-b/←/→ колонки,
  PgUp/PgDn страница, Home/End и C-a/C-e первый/последний.
- Запрос: C-u очистить, C-h/BS backspace, C-w очистить (файлы: затем вверх),
  C-k в prompt — kill-to-end (после перевода промпта в insert-режим).
- Действия: Enter/Tab открыть, C-t вкладка, C-o/C-v сплиты, C-d удалить
  буфер, C-s порядок сортировки, C-l цикл режима отображения, C-i иконки,
  C-Space/P превью, Esc/C-c/C-g закрыть.
- Ограничения: h/j/k/l не трогаем (буквы фильтра); C-s не вешаем в
  standalone (terminal suspend); паритет standalone/float.

## Режимы отображения (eza-подход)

- Источник: метаданные только по видимым строкам (serve: запрос M по
  индексу; standalone: fs::metadata лениво). Кэш листинга не зависит от
  режима.
- grid — текущий (row-major, имя+цвет).
- long — строка на файл: perms uid size mtime name (как eza -l),
  human-readable размер, --time-style.
- custom — колонки по выбору: name/size/mtime/user/group/perm/mode/inode/
  type/ext; конфиг g:LustyExplorerColumns / LUSTY_COLUMNS / --columns.
- Сортировки: name|size|time|ext|type, --reverse, --group-dirs-first.
- Иконки (nerd font) опционально; tree-вид позже.
- Приоритет опций: CLI > env LUSTY_* > g:LustyExplorer*.

## Превью (панель справа)

- Файл текст (head, подсветка), файл бинарь (MIME+hexdump), изображение
  (kitty protocol / degrade), каталог (мини-листинг), буфер (C-b), grep-hit
  (контекст вокруг), git-diff фрагмент, метаданные stat, recent (голова).
- Переключение C-Space/P; ширина LUSTY_PREVIEW_WIDTH; асинхронно,
  debounce, отмена устаревших; лимиты LUSTY_PREVIEW_MAX_BYTES;
  graceful degrade без изображений/nerd font.

## Порядок работ

- A: докрутить хоткеи, паритет standalone/float.
- B: long-режим + сортировки (сначала standalone, затем float).
- C: custom-колонки + env/config + иконки.
- D: превью текст/каталог/буфер/grep (float, затем standalone).
- E: изображения, git-diff, man.
- F: тесты (serve M, long/custom смоук), доки, бенчмарки.
