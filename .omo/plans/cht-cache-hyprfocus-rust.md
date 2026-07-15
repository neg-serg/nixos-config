# Plan: cht-cache-hyprfocus-rust

## TL;DR (For humans)

**Проблема:** бенчмарк показал 2 скрипта с аномально долгим стартом:
- `cht` — 528ms (curl к cheat.sh по сети)
- `hypr-focus-hist` — 2002ms (Python, тяжелый импорт)

**Что делаем:**

### Трек A: `cht` — кеширование
Модифицируем `cht` чтобы кешировать ответы в `~/.cache/cht/`. Первый запрос темы идёт в сеть (как сейчас), последующие — мгновенно из кеша. TTL 7 дней, принудительное обновление через `cht --refresh <topic>`.

### Трек B: `hypr-focus-hist` → Rust + новые фичи
Переписываем на Rust с крейтом `hyprland` (0.4.0-beta.3). Единый бинар с двумя режимами:
- **daemon** — фоновый трекинг истории фокуса (как текущий Python)
- **commands** — one-shot операции: фокус по истории, прыжок на workspace, перемещение окна, переключение раскладок/флоатинга/фуллскрина/пина

Пакетируем как `packages/hypr-focus/` → `pkgs.neg.hypr-focus` → заменяет Python-скрипт в `~/.local/bin/`.

**Результат:** оба скрипта стартуют <5ms вместо 500-2000ms, плюс hypr-focus получает расширенный набор оконных операций в одном бинаре.

---

## Todos

- [x] 1. cht: добавить локальное кеширование (~/.cache/cht/, TTL 7d, --refresh)
- [x] 2. hypr-focus: создать Rust проект (Cargo.toml, main.rs, default.nix)
- [x] 3. hypr-focus: зарегистрировать в оверлее (tools.nix)
- [x] 4. hypr-focus: заменить Python на Rust бинар в local-bin.nix
- [x] 5. hypr-focus: реализовать daemon mode (event listener, focus history)
- [x] 6. hypr-focus: реализовать switch + workspace + toggle команды
- [x] 7. hypr-focus: реализовать layout + master + dwindle операции
- [x] 8. Финальная сборка, бенчмарк, документация

## Final Verification Wave

- [x] F1. Nix build + flake check проходит
- [x] F2. Бенчмарк: cht <10ms, hypr-focus <5ms
- [x] F3. Кеш cht работает (повторный вызов мгновенный)
- [x] F4. Все 15 команд присутствуют и документированы

---

### Batch 1: cht — кеширование (1 файл, быстрый win)

**Todo 1.1: Добавить кеширование в `cht`**
- **WHERE:** `/etc/nixos/packages/local-bin/bin/cht`
- **HOW:** Добавить логику:
  - Кеш-директория: `~/.cache/cht/`
  - Ключ = `sha256(query)` или `url_encode(query)` как имя файла
  - При вызове: проверить кеш → если есть и не старше 7 дней → вывести из кеша и выйти
  - При промахе: curl → сохранить в кеш → вывести
  - Флаг `--refresh`: пропустить кеш, принудительно обновить
- **EXPECT:** `cht python list comprehension` первый раз ~500ms, второй раз <5ms
- **QA:** Запустить `cht python list` дважды, убедиться что второй раз мгновенный. Проверить `cht --refresh python list` — должен пойти в сеть. Проверить что файлы кеша создаются в `~/.cache/cht/`.
- **Commit:** `[cli/cht] Add local response cache with 7-day TTL`

---

### Batch 2: hypr-focus — Rust проект и базовая структура (4 файла, скелет)

**Todo 2.1: Создать Rust проект `packages/hypr-focus/`**
- **WHERE:** `/etc/nixos/packages/hypr-focus/`
- **HOW:** Создать Cargo.toml с зависимостью `hyprland = "0.4.0"`, src/main.rs с argparse (clap), src/daemon.rs, src/commands.rs, и `default.nix` по шаблону `pwroute/default.nix`.
  - `Cargo.toml`: name="hypr-focus", deps: hyprland={version="0.4", features=["listener","dispatch"]}, clap
  - `default.nix`: `rustPlatform.buildRustPackage { src = ./.; cargoLock.lockFile = ./Cargo.lock; }`
  - `src/main.rs`: парсинг subcommand (daemon / switch / workspace / move / layout / toggle)
- **EXPECT:** `nix build .#hypr-focus` собирается. Бинарный файл `result/bin/hypr-focus` существует.
- **QA:** Запустить `nix build .#neg.hypr-focus && result/bin/hypr-focus --help` — должен показать список команд.
- **Commit:** `[tools/hypr-focus] Bootstrap Rust crate with clap+hyprland deps`

**Todo 2.2: Зарегистрировать пакет в оверлее**
- **WHERE:** `/etc/nixos/packages/overlays/tools.nix`
- **HOW:** Добавить `hypr-focus = callPkg (packagesRoot + "/hypr-focus") { };` в секцию `neg = ...`
- **EXPECT:** `nix eval .#neg.hypr-focus.name` выдаёт `"hypr-focus-0.1.0"`
- **QA:** `nix build .#neg.hypr-focus` — успешная сборка.
- **Commit:** `[tools/hypr-focus] Wire into overlay as pkgs.neg.hypr-focus`

**Todo 2.3: Заменить Python-скрипт на Rust бинар в local-bin.nix**
- **WHERE:** `/etc/nixos/modules/user/nix-maid/cli/local-bin.nix`
- **HOW:** 
  - Добавить `hypr-focus-hist` в список `autoSkip` (строка 34)
  - Добавить запись: `".local/bin/hypr-focus-hist" = { executable = true; source = "${pkgs.neg.hypr-focus}/bin/hypr-focus"; };`
  - Убедиться что `hypr-focus` бинар находится в правильном пути
- **EXPECT:** После `nixos-rebuild switch`, `~/.local/bin/hypr-focus-hist` — symlink на Rust бинар. `hypr-focus-hist --help` работает.
- **QA:** `which hypr-focus-hist` → `/home/neg/.local/bin/hypr-focus-hist`. `readlink $(which hypr-focus-hist)` → путь в nix store.
- **Commit:** `[cli/hypr-focus] Replace Python daemon with Rust binary in local-bin`

---

### Batch 3: hypr-focus — daemon mode (фокус-история, 2 файла)

**Todo 3.1: Реализовать daemon mode (трекинг истории фокуса)**
- **WHERE:** `/etc/nixos/packages/hypr-focus/src/daemon.rs`
- **HOW:** Порт логики из Python:
  - `EventListener::new()` → слушать `activewindowv2>>` и `closewindow>>`
  - Хранить ordered list (Vec<Address>) до 20 записей
  - Записывать предыдущее окно в state file: `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/focus-history`
  - Auto-reconnect при разрыве сокета (loop + sleep 3s)
  - Логгирование в `/tmp/hypr-focus-hist.log` (как в Python)
  - Notify-send через `std::process::Command` для уведомлений об ошибках
- **EXPECT:** `hypr-focus daemon` работает идентично Python-версии: пишет в state file, реконнектится.
- **QA:** Запустить daemon, переключить окна, проверить `/tmp/hypr-focus-hist.log` на наличие событий. Убить Hyprland, убедиться что daemon переподключается.
- **Commit:** `[tools/hypr-focus] Implement daemon mode — focus history tracking`

**Todo 3.2: Реализовать switch mode (переключение на предыдущее окно)**
- **WHERE:** `/etc/nixos/packages/hypr-focus/src/commands.rs`
- **HOW:** `hypr-focus switch`:
  - Читает state file
  - Вызывает `Dispatch::FocusWindow(WindowIdentifier::Address(addr))`
  - Выводит ошибку через `notify-send` если нет истории
- **EXPECT:** `hypr-focus switch` работает идентично `hypr-focus-hist --switch`.
- **QA:** Переключить окна, запустить `hypr-focus switch`, убедиться что фокус вернулся на предыдущее.
- **Commit:** `[tools/hypr-focus] Implement switch command — focus previous window`

---

### Batch 4: hypr-focus — workspace operations (2 файла)

**Todo 4.1: Workspace jump — переключение на workspace**
- **WHERE:** `/etc/nixos/packages/hypr-focus/src/commands.rs`
- **HOW:** `hypr-focus workspace <id|name>`:
  - Вызывает `Dispatch::Workspace(WorkspaceIdentifierWithSpecial::Id(i32) или Name(String))`
- **EXPECT:** `hypr-focus workspace 3` = переключение на workspace 3.
- **QA:** `hypr-focus workspace 1` → проверить что активный workspace стал 1.
- **Commit:** `[tools/hypr-focus] Add workspace jump command`

**Todo 4.2: Window to workspace + follow**
- **WHERE:** `/etc/nixos/packages/hypr-focus/src/commands.rs`
- **HOW:** `hypr-focus move-to-workspace <id> [--follow]`:
  - `Dispatch::MoveToWorkspace(WorkspaceIdentifierWithSpecial::Id(id), None)`
  - Если `--follow`: после перемещения окна, переключиться на этот workspace
- **EXPECT:** `hypr-focus move-to-workspace 5 --follow` = активное окно перемещается на workspace 5, мы следуем за ним.
- **QA:** Открыть окно на workspace 1, `hypr-focus move-to-workspace 5 --follow`. Проверить что окно на workspace 5 и мы там же.
- **Commit:** `[tools/hypr-focus] Add move-to-workspace with optional follow`

---

### Batch 5: hypr-focus — toggle operations (float, fullscreen, pin) (2 файла)

**Todo 5.1: Toggle floating**
- **WHERE:** `/etc/nixos/packages/hypr-focus/src/commands.rs`
- **HOW:** `hypr-focus float` → `Dispatch::ToggleFloating(None)`
- **QA:** `hypr-focus float` на тайловом окне → становится плавающим. Повтор → обратно тайловое.

**Todo 5.2: Toggle fullscreen + toggle pin**
- **WHERE:** `/etc/nixos/packages/hypr-focus/src/commands.rs`
- **HOW:** 
  - `hypr-focus fullscreen` → `Dispatch::ToggleFullscreen(FullscreenType::Maximize)`
  - `hypr-focus pin` → `Dispatch::TogglePin`
- **QA:** `hypr-focus fullscreen` → окно на весь экран. `hypr-focus pin` → окно видно на всех workspace.

**Commit (5.1 + 5.2 вместе):** `[tools/hypr-focus] Add float, fullscreen, and pin toggle commands`

---

### Batch 6: hypr-focus — layout operations (tiling) (3 файла)

**Todo 6.1: Layout switching (master ↔ dwindle с автоопределением)**
- **WHERE:** `/etc/nixos/packages/hypr-focus/src/commands.rs`
- **HOW:** `hypr-focus layout [master|dwindle]`:
  - Без аргументов — читает текущий layout через `hyprland::data::*` и переключает на противоположный (master→dwindle, dwindle→master)
  - С именем — прямое переключение через `Keyword::set("general:layout", name)`
  - **Верификация:** `Keyword::set("general:layout", ...)` — стандартный hyprctl keyword, работает в любом Hyprland. `hy3` исключён — плагин не установлен в рабочей конфигурации (только в тестовом файле `tests/hyprland-startup.nix`). Архитектура позволяет добавить hy3 позже через конфиг.
- **EXPECT:** `hypr-focus layout` → мгновенный toggle master↔dwindle.
- **QA:** `hypr-focus layout` из master → dwindle. Ещё раз → master. `hypr-focus layout dwindle` → прямое переключение.
- **Валидность команды:** ✅ `hyprctl keyword general:layout master` / `hyprctl keyword general:layout dwindle` — задокументированные Hyprland keyword-команды.

**Todo 6.2: Master layout operations (orientation, mfact, swap, add/remove master)**
- **WHERE:** `/etc/nixos/packages/hypr-focus/src/commands.rs`
- **HOW:**
  - `hypr-focus orientation` → `Dispatch::OrientationNext` (left→right→top→bottom)
  - `hypr-focus split-ratio <+0.1|-0.1>` → `Dispatch::Custom("splitratio", val)` (mfact)
  - `hypr-focus split-ratio <0.3..0.9>` → set exact mfact via `Dispatch::Custom("splitratio", "exact")` / keyword
  - `hypr-focus swap-master` → `Dispatch::SwapWithMaster(SwapWithMasterParam::Next)`
  - `hypr-focus add-master` → `Dispatch::Custom("layoutmsg", "addmaster")`
  - `hypr-focus remove-master` → `Dispatch::Custom("layoutmsg", "removemaster")`
- **EXPECT:** Полный контроль над мастер-лейаутом одной командой.
- **QA:** `hypr-focus add-master` — появляется новое мастер-окно. `hypr-focus swap-master` — следующее становится мастером.

**Todo 6.3: Dwindle layout operations (togglesplit, preselect)**
- **WHERE:** `/etc/nixos/packages/hypr-focus/src/commands.rs`
- **HOW:**
  - `hypr-focus toggle-split` → `Dispatch::ToggleSplit` (горизонтальный ↔ вертикальный сплит)
  - `hypr-focus preselect <l|r|u|d>` → `Dispatch::Custom("layoutmsg", "preselect l/r/u/d")`
- **EXPECT:** Dwindle-специфичные операции.
- **QA:** В dwindle режиме: `hypr-focus preselect r` → открыть новое окно → оно справа.

**Commit (6.1 + 6.2 + 6.3 вместе):** `[tools/hypr-focus] Add full layout cycle (master/dwindle/hy3), orientation, mfact, master add/remove, dwindle split/preselect`

---

### Batch 7: Финальная сборка, тестирование, и документирование (3 файла)

**Todo 7.1: Интеграционное тестирование**
- **WHERE:** `/etc/nixos/packages/hypr-focus/`
- **HOW:**
  - `nix build .#neg.hypr-focus` — успешно
  - `nix flake check` — без ошибок
  - Проверить что `hypr-focus daemon` запускается и логирует события
  - Проверить что `hypr-focus switch` работает
  - Проверить все команды из batches 4-6 (workspace, float, fullscreen, pin, layout, orientation, swap-master)
  - Проверить что `cht python list` кешируется и второй вызов мгновенный
- **EXPECT:** Все тесты проходят, скрипты работают.
- **QA:** Ручной прогон всех команд в работающей Hyprland сессии.

**Todo 7.2: Бенчмарк после оптимизации**
- **WHERE:** Повторный запуск бенчмарка
- **HOW:** Запустить тот же Python-бенчмарк из начала сессии, сравнить `cht` и `hypr-focus-hist` до/после.
- **EXPECT:** `cht` <10ms (из кеша), `hypr-focus-hist` <5ms.
- **QA:** Сравнить результаты.

**Todo 7.3: Документация (README / help)**
- **WHERE:** `/etc/nixos/packages/hypr-focus/README.md`
- **HOW:** 
  - Описание всех команд с примерами
  - Как запустить daemon (`hypr-focus daemon` — в автозапуск)
  - Как привязать к хоткеям в hyprland.lua
- **Commit:** `[tools/hypr-focus] Add README with usage examples and hotkey binding guide`

---

## Dependency Matrix

```
Batch 1 (cht)         — независим, можно делать первым
Batch 2 (rust skeleton) — независим, можно параллельно с Batch 1
Batch 3 (daemon+switch) — зависит от Batch 2
Batch 4 (workspace)     — зависит от Batch 2
Batch 5 (toggles)       — зависит от Batch 2
Batch 6 (layout)        — зависит от Batch 2
Batch 7 (final testing) — зависит от Batch 1-6
```

Batch 3, 4, 5, 6 можно делать параллельно после Batch 2.

## Command Verification (проверка что операции реально работают)

Каждая команда проверена против реальной конфигурации Hyprland (`hyprland.lua`, `modules/`) и документации hyprctl. Источник валидности указан.

| Команда hypr-focus | Эквивалент hyprctl | Доказательство работы |
|---|---|---|
| `switch` | `hyprctl dispatch focuswindow address:0x...` | ✅ Используется в текущем Python-скрипте `hypr-focus-hist:75` |
| `workspace <id>` | `hyprctl dispatch workspace <id>` | ✅ Стандартный диспетчер Hyprland |
| `move-to-workspace <id>` | `hyprctl dispatch movetoworkspace <id>` | ✅ Используется в `hypr-rearrange.py:357` (`movetoworkspacesilent`) |
| `float` | `hyprctl dispatch togglefloating` | ✅ Используется в `hyprland.lua:281` (`hl.dsp.window.float`) |
| `fullscreen` | `hyprctl dispatch fullscreen` | ✅ Используется в `hyprland.lua:164,282-283` |
| `pin` | `hyprctl dispatch pin` | ✅ Используется в window rules `hyprland.lua:392,435` |
| `layout master\|dwindle` | `hyprctl keyword general:layout <name>` | ✅ Hyprland keyword API, стандартный механизм |
| `orientation` | `hyprctl dispatch layoutmsg orientationnext` | ✅ Стандартный диспетчер master-лейаута |
| `split-ratio ±0.1` | `hyprctl dispatch splitratio ±0.1` | ✅ Используется в `hyprland.lua:232-233` |
| `split-ratio 0.3..0.9` | `hyprctl keyword master:mfact <val>` | ✅ Hyprland keyword для установки mfact |
| `swap-master` | `hyprctl dispatch layoutmsg swapwithmaster` | ✅ Стандартный диспетчер master-лейаута |
| `add-master` | `hyprctl dispatch layoutmsg addmaster` | ✅ Стандартный диспетчер master-лейаута |
| `remove-master` | `hyprctl dispatch layoutmsg removemaster` | ✅ Стандартный диспетчер master-лейаута |
| `toggle-split` | `hyprctl dispatch togglesplit` | ✅ Стандартный диспетчер dwindle-лейаута |
| `preselect <dir>` | `hyprctl dispatch layoutmsg preselect <dir>` | ✅ Используется в Hyprland dwindle layout |

**Исключено из плана:**
- **hy3** — плагин НЕ установлен в рабочей конфигурации (`modules/user/session/default.nix:18` — `package = pkgs.hyprland`, без плагинов). Есть только в тесте `tests/hyprland-startup.nix:9-11`. Архитектура `hypr-focus` позволяет добавить hy3 в цикл позже — достаточно передать имя раскладки.

## Must-NOT-Have

- **Не трогать:** `screenrec`, `screenshot`, `swayimg-actions.sh`, `wl-restart`, `wl-restore`, `main-menu`, `surfingkeys-server`, и все графические/UI скрипты.
- **Не менять** поведение `cht` при отсутствии кеша — первый запрос идёт в сеть как и раньше.
- **Не удалять** Python-скрипт `hypr-focus-hist` до подтверждения что Rust-версия работает (оставить в `packages/local-bin/bin/` как fallback, просто исключить из auto-установки).
- **Не добавлять** GUI/интерактивные фичи — только CLI/daemon.
- **Не менять** структуру оверлея или систему пакетирования.
