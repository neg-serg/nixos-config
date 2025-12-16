# Шейдеры Quickshell и клин wedge

Этот файл описывает, как устроены шейдеры, клип-эффект «клина» и как их собирать/отлаживать.

### Обзор

- Используется Qt 6 `ShaderEffect` с заранее скомпилированными `.qsb` шейдерами.
- Основная задача — вычесть треугольный клин ("wedge") из краёв левой/правой панелей, чтобы через
  отверстие было видно «шов» по центру.
- Все `.frag` источники собираются в `.qsb` с помощью `qsb` (пакет `qt6.qtshadertools`).

### Файлы

- Шейдер клипа: `shaders/wedge_clip.frag` (+ собранный `shaders/wedge_clip.frag.qsb`)
- Встроенные шейдеры шва/тоновки: `shaders/seam*.frag(.qsb)`, `shaders/panel_tint_mix.frag(.qsb)`,
  `shaders/diag.frag(.qsb)`
- Скрипт сборки: `scripts/compile_shaders.sh`
- Интеграция: `Bar/Bar.qml`

### Сборка шейдеров

1. Установить инструменты: `nix shell nixpkgs#qt6.qtshadertools`
1. Из каталога `~/.config/quickshell` запустить:
   ```bash
   nix shell nixpkgs#qt6.qtshadertools -c bash -lc 'scripts/compile_shaders.sh'
   ```

Примечания:

- Qt 6 требует предварительной компиляции в формат `.qsb`. Прямые пути на `.frag` больше не
  поддерживаются.
- Скрипт собирает все `*.frag` → `*.frag.qsb` для GLSL профилей `100es,120,150`.

### Параметры шейдера клипа (wedge_clip.frag)

Буфер `qt_ubuf` содержит 3 вектора `vec4` с параметрами:

- `params0` — `x` ширина клина в долях ширины (0..1), `y` направление диагонали (slopeUp: 1 ↑, 0 ↓),
  `z` сторона клина (`+1` у правого края, `-1` у левого), `w` — не используется.
- `params1` — `x` перо/растушёвка границы (0..~0.25), `yzw` — не используются.
- `params2` — отладка: `x` — непрозрачность мадженты внутри клина, `y` — принудительное рисование
  мадженты поверх всего прямоугольника (проверка, что сам `ShaderEffect` вообще отрисовывается).

Семплер `sourceSampler` — это исходное содержимое (цветная заливка панели или оверлей‑тинт), которое
клипуется шейдером.

### Включение/отладка (переменные окружения)

- `QS_ENABLE_WEDGE_CLIP=1` — включить путь шейдера клипа.
- `QS_WEDGE_WIDTH_PCT=NN` — ширина клина в процентах (0..100). Если не задано, берётся от геометрии
  `seamPanel.seamWidthPx`.
- `QS_WEDGE_DEBUG=1` — включает отладочные оверлеи (Canvas‑клины поверх панелей и маджента внутри
  клипа).
- `QS_WEDGE_SHADER_TEST=1` — шейдер рисует мадженту по всей области эффекта (проверка, что сам
  ShaderEffect виден на экране).
- Проверочный полноэкранный тинт удалён; для проверки видимости используйте `QS_WEDGE_DEBUG=1` или
  временно поднимите панели на слой `WlrLayer.Overlay`.

### Интеграция в QML (вкратце)

- В `Bar/Bar.qml` для левой и правой панели используются `Loader` с `ShaderEffect`, где подключён
  `../shaders/wedge_clip.frag.qsb`.
- Источник (`sourceSampler`) — `ShaderEffectSource` от прямоугольника заливки панели или тинта.
- При активном шейдере скрываютсяfallback‑маски `OpacityMask` (чтобы не перекрывать результат
  шейдера).
- На время отладки (при `QS_WEDGE_DEBUG=1`) панели переводятся на слой `WlrLayer.Overlay`, чтобы
  исключить перекрытия композитора.

### Диагностика «клин не виден»

1. Сначала проверить сборку: нет ли в логах Qt предупреждения про «Failed to find shader … .qsb».
1. Запустить с жёсткими флагами:
   ```bash
   QS_ENABLE_WEDGE_CLIP=1 QS_WEDGE_DEBUG=1 QS_WEDGE_SHADER_TEST=1 qs
   ```
   Должна появиться маджента поверх клипа на обеих панелях. Если нет — проблема со стеком
   слоёв/видимостью окна.
1. Проверить, что сами оконные поверхности видимы: оставьте `QS_WEDGE_DEBUG=1` (панели перейдут на
   `WlrLayer.Overlay`) и убедитесь, что маджента следует за окном.
1. Если ShaderEffect виден, но треугольник не «вырезается», увеличить ширину:
   `QS_WEDGE_WIDTH_PCT=60` (или 80).
1. Убедиться, что источники скрываются: `ShaderEffectSource.hideSource` привязан к активности
   соответствующего `Loader` (иначе оригинальные прямоугольники поверх/под шейдером скрывают
   «дырку»).

Скриншот (Wayland): `grim -g "$(slurp)" wedge.png`.

### Ограничения/заметки

- Миграция на чистый шейдер‑путь: после успешной верификации можно удалить старые
  Canvas/OpacityMask‑fallback.
- Производительность: эффекты работают поверх панелей; все источники идут через `ShaderEffectSource`
  (live, recursive), что имеет накладные расходы — держать логи включенными только на отладку.

### Взаимодействие с прозрачностью панелей

- При высокой прозрачности фон панелей становится менее заметным — визуально «сила» клина
  (вырезанного треугольника) тоже кажется меньше. Это ожидаемо: клин вычитает из базовой заливки
  панели. Если нужно усилить эффект — увеличьте ширину клина (`QS_WEDGE_WIDTH_PCT`) или уменьшите
  прозрачность панели (см. `Docs/PANELS.md`).
- В отладке панели могут быть на `WlrLayer.Overlay` — тогда «дырка» клина показывает то, что под
  окном панели на уровне композитора. В обычном режиме слой `Top`.
- Параметры авто‑ширины: по умолчанию берем `min(seamWidthPx, 0.35 * faceWidth) / faceWidth` и затем
  ограничиваем в [0.02..0.98]. Переменная окружения `QS_WEDGE_WIDTH_PCT` (0..100) переопределяет это
  поведение.
- Перо/растушёвка границы: `params1.x` вычисляется из радиуса темы и масштаба и далее ограничивается
  примерно до 0.05 относительно ширины панели.
- Смешивание: в `ShaderEffect` включено `blending: true`; Qt Quick использует premultiplied alpha,
  шейдер отдаёт уменьшенную альфу внутри клина.

### Что уже поймали (проблемы и решения)

- Ошибка `Failed to find shader … .qsb` — шейдер не собран или путь указан неверно. Решение:
  запустить сборку из каталога `~/.config/quickshell` или дать полный путь к скрипту. Убедиться, что
  `fragmentShader: Qt.resolvedUrl("../shaders/<name>.frag.qsb")`.
- Ошибка `qsb: Unknown options: vk, sl` — в вашей версии `qsb` нет флагов Vulkan/Spir-V. Решение:
  использовать только `--glsl "100es,120,150"`.
- «Ничего не меняется» — клин не виден, хотя `QS_ENABLE_WEDGE_CLIP=1`:
  - Частая причина — базовые прямоугольники панелей (`leftBarFill/rightBarFill`) и/или их тинты всё
    ещё рисуются под/над шейдером и визуально закрывают «дырку». Нужно отключать исходные слои,
    когда активен шейдер, и оставлять только шейдерную версию. Аналогично — выключать fallback
    `OpacityMask` в этом режиме.
  - Убедиться, что `ShaderEffect` действительно отрисовывается: `QS_WEDGE_SHADER_TEST=1` (в этом
    режиме маджента закрашивает всю область эффекта).
  - Проверить видимость самих окон панелей: оставьте `QS_WEDGE_DEBUG=1`, панели перейдут на
    `WlrLayer.Overlay`, что гарантирует отсутствие перекрытий от других окон.
- Нулевая высота окна с шейдерами — Seam панель может «схлопнуться» до 0px и шейдеры становятся
  невидимыми. Решение: дать `implicitHeight` и показывать её после «готовности геометрии».
- Путаемся с рабочим каталогом — вызов `scripts/compile_shaders.sh` вне каталога конфигурации
  приводит к `No such file or directory`. Решение: запускать из `~/.config/quickshell` или явно
  `cd ~/.config/quickshell && scripts/compile_shaders.sh`.

### План доработок

1. Спрятать исходные прямоугольники заливки/тинтов, когда активен путь шейдера (оставить только
   ShaderEffect-версии).
1. После подтверждения визуального результата удалить Canvas/OpacityMask‑fallback и вернуть слои
   панелей с Overlay на обычный Top.
1. Экспонировать ширину клина через `Settings` (перенести с env при желании).
1. Подточить производительность: ограничить `ShaderEffectSource` по области, снизить
   `live/recursive`, если это допустимо.
1. В документации закрепить «чек‑лист» отладки и добавить примеры команд для скриншотов (Wayland:
   `grim`, `slurp`).

______________________________________________________________________

## English (EN)

### Overview

- Uses Qt 6 `ShaderEffect` with precompiled `.qsb` shaders.
- Goal: subtract a triangular wedge from the left/right bar faces so the central seam shows through.
- All `.frag` sources are compiled to `.qsb` via `qsb` (Qt Shader Tools).

### Files

- Clip shader: `shaders/wedge_clip.frag` (+ compiled `shaders/wedge_clip.frag.qsb`)
- Seam/tint helpers: `shaders/seam*.frag(.qsb)`, `shaders/panel_tint_mix.frag(.qsb)`,
  `shaders/diag.frag(.qsb)`
- Build script: `scripts/compile_shaders.sh`
- QML integration: `Bar/Bar.qml`

### Build the shaders

1. Get tools: `nix shell nixpkgs#qt6.qtshadertools`
1. From `~/.config/quickshell` run:
   ```bash
   nix shell nixpkgs#qt6.qtshadertools -c bash -lc 'scripts/compile_shaders.sh'
   ```

Notes:

- Qt 6 requires `.qsb`; raw `.frag` files aren’t accepted by `ShaderEffect` anymore.
- The script compiles all `*.frag` → `*.frag.qsb` targeting GLSL `100es,120,150`.

### wedge_clip.frag parameters

`qt_ubuf` contains three `vec4` parameter blocks:

- `params0`: `x` wedge width normalized (0..1), `y` slopeUp (1 = bottom→top, 0 = top→bottom), `z`
  side (`+1` right edge, `-1` left edge), `w` unused.
- `params1`: `x` feather amount (soft edge) in [0..~0.25], `yzw` unused.
- `params2`: debug — `x` overlay opacity inside the wedge, `y` force-paint whole rect with magenta
  (to verify the ShaderEffect is visible).

`sourceSampler` is the input (bar face or tint) that the shader clips.

### Runtime toggles (env)

- `QS_ENABLE_WEDGE_CLIP=1` — enable the shader path.
- `QS_WEDGE_WIDTH_PCT=NN` — wedge width in percent (0..100). Defaults to a value derived from
  `seamPanel.seamWidthPx`.
- `QS_WEDGE_DEBUG=1` — enables visual debug overlays (Canvas wedges + shader magenta overlay).
- `QS_WEDGE_SHADER_TEST=1` — shader paints magenta across the whole rect (visibility check).
- `QS_WEDGE_TINT_TEST` was removed; use `QS_WEDGE_DEBUG=1` combined with `WlrLayer.Overlay` to
  confirm the layer-shell windows are visible.

### QML integration (short)

- In `Bar/Bar.qml`, left/right faces use a `Loader` with a `ShaderEffect` whose `fragmentShader`
  points to `../shaders/wedge_clip.frag.qsb`.
- The shader samples a `ShaderEffectSource` of the bar face (or tint) and subtracts a triangle near
  the inner edge.
- When the shader is active, legacy `OpacityMask` fallbacks are hidden to avoid overpainting.
- In debug mode (`QS_WEDGE_DEBUG=1`) bars are temporarily placed on `WlrLayer.Overlay` to rule out
  compositor stacking issues.

### Troubleshooting “wedge not visible”

1. Verify build: no “Failed to find shader … .qsb” warnings in logs.
1. Run a hard visibility test:
   ```bash
   QS_ENABLE_WEDGE_CLIP=1 QS_WEDGE_DEBUG=1 QS_WEDGE_SHADER_TEST=1 qs
   ```
   You should see magenta over the effect area. If not, it’s a stacking/visibility issue (not the
   shader).
1. Confirm the layer-shell windows are visible: keep `QS_WEDGE_DEBUG=1` running (bars move to
   `WlrLayer.Overlay`) and check whether the magenta overlay tracks the window.
1. If ShaderEffect is visible but the wedge is still subtle, increase width: `QS_WEDGE_WIDTH_PCT=60`
   (or 80).
1. Ensure sources are hidden: bind `ShaderEffectSource.hideSource` to the corresponding clip
   `Loader.active`, otherwise the original rectangles over/under the effect will visually fill the
   “hole”.

Wayland screenshot: `grim -g "$(slurp)" wedge.png`.

### Notes / limitations

- After validation, prefer the shader-only path and remove the legacy Canvas/OpacityMask fallbacks.
- Performance: ShaderEffect/ShaderEffectSource are live and recursive; keep verbose debug disabled
  outside troubleshooting.

### Interaction with panel transparency

- High panel transparency reduces the visual prominence of the wedge because the shader subtracts
  from the panel fill. If you want a stronger look, increase wedge width (`QS_WEDGE_WIDTH_PCT`) or
  decrease panel transparency (see `Docs/PANELS.md`).
- During debug, bars can be on `WlrLayer.Overlay`; the wedge then reveals whatever is under the
  panel window in the compositor. In normal runs the layer is `Top`.
- Auto width defaults to `min(seamWidthPx, 0.35 * faceWidth) / faceWidth`, clamped to [0.02..0.98].
  `QS_WEDGE_WIDTH_PCT` (0..100) overrides.
- Feather: `params1.x` derives from theme radius and scale, capped at ~0.05 relative to face width.
- Blending is enabled; Qt Quick uses premultiplied alpha; inside the wedge alpha is reduced toward
  zero.

### Issues we hit (and fixes)

- `Failed to find shader … .qsb` — shader not built or wrong path. Fix: run the build from
  `~/.config/quickshell` (or use the full path) and ensure `fragmentShader` points to
  `../shaders/<name>.frag.qsb`.
- `qsb: Unknown options: vk, sl` — your `qsb` doesn’t support Vulkan/Spir-V flags. Fix: use GLSL
  only `--glsl "100es,120,150"`.
- “Nothing changes” even with `QS_ENABLE_WEDGE_CLIP=1`:
  - Most common: the original bar fill/tint rectangles still render under/over the shader and
    visually cover the hole. Hide them when the shader path is active and show only the ShaderEffect
    variants. Also ensure all `OpacityMask` fallbacks are disabled in shader mode.
  - Verify ShaderEffect is actually painting: `QS_WEDGE_SHADER_TEST=1` (magenta over the whole
    rect).
  - Confirm the bar windows are visible: keep `QS_WEDGE_DEBUG=1` running so the bars stay on
    `WlrLayer.Overlay` and the magenta overlay follows the window.
  - Z-order during debug: raise the clip Loaders (e.g., `z: 50`) so their output is not hidden;
    avoid seam overlays on top while validating.
  - Logging: enable `Settings.json` → `"debugLogs": true` to get lines like
    `[bar:left] wedge shader active: true …` and overlay geometry logs.
- Zero-height shader window — the seam window may collapse to 0px; nothing renders. Fix: give it
  `implicitHeight` and show after geometry readiness.
- Working directory confusion — invoking `scripts/compile_shaders.sh` outside the config dir fails.
  Fix: run it from `~/.config/quickshell` or `cd` there first.

### Next steps

1. Keep the shader-only path; leave debug/test flags off by default.
1. Optionally expose wedge width in persistent Settings (not only env).
1. Improve performance: reduce `ShaderEffectSource` region to the wedge strip; review
   `live/recursive`.
1. Polish visuals: tune `feather` using theme radius/scale; keep left/right in sync.
1. Add a small Settings toggle to reset width env overrides.
1. Keep `scripts/compile_shaders.sh` documented as the canonical rebuild step.

______________________________________________________________________

## Итоги (что получилось / что не получилось)

Что получилось:

- Сборка `.qsb` через `qsb --glsl "100es,120,150"` (скрипт `scripts/compile_shaders.sh`) — все
  шейдеры компилируются.
- Клин (треугольное вычитание) виден на обеих панелях; `QS_WEDGE_DEBUG=1` показывает мадженту внутри
  клина; `QS_WEDGE_SHADER_TEST=1` подтверждает, что ShaderEffect реально рисуется.
- Источники скрываются при активном шейдере (`ShaderEffectSource.hideSource ← Loader.active`), чтобы
  исходные прямоугольники не закрывали «дыру».
- Z‑порядок клип‑лоадеров поднят (например, `z: 50`) для наглядности в отладке; при необходимости
  панели ставятся в `WlrLayer.Overlay`.
- Прозрачность фона панелей теперь настраивается через `panelBgAlphaScale` (см. `Docs/PANELS.md`).

Что не получилось/проблемы по пути (и как обошли):

- Флаги `qsb --vk/--sl` не поддерживаются локальной версией — перешли на GLSL‑только.
- Предупреждения «Failed to find shader … .qsb» при отсутствии сборки/неверном пути — исправили
  скриптом сборки и `Qt.resolvedUrl("../shaders/*.frag.qsb")`.
- «Клина не видно» — из‑за того, что исходные прямоугольники панели/тинта продолжали рисоваться
  под/над эффектом. Решение: `hideSource` + отключить fallback‑маски, при отладке поднять `z` и/или
  слой.
- Логи Component.onCompleted иногда не доходили — включили `Settings.json → debugLogs: true` и
  дополнили видимыми overlay‑логами.
- Путаница с рабочим каталогом для скрипта — запускать из `~/.config/quickshell`.

Оставшиеся идеи/потенциальные доработки:

- Экспонировать ширину/наклон клина в Settings (сейчас есть env и slope‑флаги).
- Урезать область `ShaderEffectSource` до полосы клина (меньше перерисовок), пересмотреть
  `live/recursive`.
- Тонкая настройка перьев/скруглений под тему и масштаб.

______________________________________________________________________

## Summary (what worked / what didn’t)

Worked:

- QSB builds (`qsb --glsl "100es,120,150"`) via `scripts/compile_shaders.sh`; all shaders compile.
- Wedge subtraction visible on both bars; `QS_WEDGE_DEBUG=1` shows magenta overlay;
  `QS_WEDGE_SHADER_TEST=1` proves ShaderEffect paints.
- Sources are hidden when the shader is active (`ShaderEffectSource.hideSource ← Loader.active`) so
  the original rects don’t fill the hole.
- Raised z for clip loaders (e.g., `z: 50`) and optional `WlrLayer.Overlay` during debug to ensure
  visibility.
- Panel background transparency is configurable via `panelBgAlphaScale` (see `Docs/PANELS.md`).

Didn’t work initially / issues encountered (and fixes):

- Local `qsb` doesn’t accept `--vk/--sl` → use GLSL only.
- “Failed to find shader … .qsb” when not compiled or wrong path → fixed with build script and
  `Qt.resolvedUrl("../shaders/*.frag.qsb")`.
- “Wedge not visible” because original fills/tints still painted → fixed with `hideSource` and by
  removing fallbacks; raised `z`/Overlay for debugging.
- Logging not always visible → enabled `debugLogs` in `Settings.json` and relied on overlay logs.
- Working directory confusion → run `scripts/compile_shaders.sh` from `~/.config/quickshell`.

Open items / potential follow‑ups:

- Expose wedge width/slope in persistent Settings (beyond env and slope flags).
- Limit `ShaderEffectSource` to the wedge strip; review `live/recursive` for perf.
- Fine‑tune feather based on theme and scaling.
