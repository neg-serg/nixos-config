# Бэклог (collab / browser / computer / vibe / autoresearch): ресёрч «как делать»

Дата: 2026-08-20. Ресёрч первоисточников + локальной инфраструктуры DSH на odin.
Пять направлений из agent-deferred §11-13, для каждого — факты, паттерн «как надо»,
реализация в DSH, риски, оценка. Выводы: что закрыть как покрытое, что делать следующим.

## 0. Локальная база (что уже есть)

- Локальный Ollama на odin (ROCm): qwen3:8b-q8_0 (быстрый), gemma4:12b, qwen3-coder:30b,
  **qwen2.5vl:7b-q8_0 (vision!)** — для понимания скриншотов, данные не уходят из хоста.
- DSH: субагенты persistent + `send_message` (адресуемость воркеров), `dsh-tool-web`
  (только web_search; `fetch: false` на хосте — политика), `tools.restrict()` в dsh-tools
  (сужение тулов скоупа), веб-GUI multi-session, `dsh-api-remotes`/`dsh-client-connection`.
- Уже портировано: vibe-director воркфлоу (omp ln-режим), boulder (todo-контроль),
  ab-bench.mjs (A/B промптов), code-review.mjs (git diff → модель).

## 1. collab — live-коллаборация

**Факты**
- В DSH базовый коллаб уже есть: веб-GUI (несколько сессий), субагенты (persistent,
  addressable), `send_message` — это и есть «директор → воркеры» на живых сессиях.
- Официальный `deepseek-harness-agentchat` (npm 0.1.0) — мост к ВНЕШНЕМУ AgentChat-сервису
  (OpenClaw 方言, outbound WS, `uin`-аккаунты, QQ-стиль, китайский стек). Для нас не
  релевантен: внешний сервис + китайский интерфейс (пользователь не читает китайский).
- `dsh-api-remotes` / `dsh-client-connection` — слой клиент-серверных соединений DSH.

**Как делать надо (если когда-то)**
- Референс relay-архитектуры: AgentWorkforce/relay ARCHITECTURE.md.
- E2E (AES) поверх WS для multi-user; изоляция сессий по скоупу (как worker ids в vibe).
- НЕ изобретать транспорт: DSH уже имеет client-connection; строить поверх него.

**Вывод**: НЕ начинать. Локальная коллаборация (сессии + субагенты) покрыта; внешний
IM-мост (agentchat) — чужой стек; relay/AES — отдельный проект без явного запроса.

## 2. browser — браузерная автоматизация

**Факты**
- `dsh-tool-web` даёт только поиск; `fetch: false` на хосте — политика безопасности.
- Браузерных тулов в профиле нет.

**Паттерн «как надо»** (browser-use: «Leaving Playwright for CDP»)
- Прямой CDP вместо Playwright: headless Chromium (`--remote-debugging-port` или pipe) +
  CDP-клиент (Runtime/Page/Input/Emulation домены). Меньше зависимостей, ближе к железу.
- Скриншот страницы → vision-модель (локальный qwen2.5vl:7b) для понимания → действия
  через Input-домен (click/type/scroll) и Page-домен (navigate/extract DOM).

**Реализация в DSH**
1. systemd-user сервис `browser-cdp`: `chromium --headless=new --remote-debugging-port=9222`
   (из nixpkgs; песочница chromium включена, НЕ `--no-sandbox`).
2. DSH-тул `browser`: navigate / screenshot / extract / click / type — с allowlist доменов,
   таймаутами; по умолчанию read-only (navigate+screenshot+extract), действия — явный вызов.
3. Vision-шаг: screenshot → локальная VL-модель (qwen2.5vl:7b), скриншоты не хранить.

**Риски**: обновления chromium в nixpkgs, память (headless ~300-500MB), DOM-хрупкость.
**Оценка**: средняя сложность; следующий кандидат после vibe/autoresearch.

## 3. computer — управление десктопом

**Факты**
- odin: Wayland + Hyprland. Никаких десктоп-примитивов в DSH нет.

**Паттерн «как надо»** — `computer-use-linux` (Rust MCP-сервер/CLI, crates.io + npm-обёртка
`@agent-sh/computer-use-linux`, prebuilt binaries; извлечён из Codex Desktop Linux):
- **Семантические селекторы через AT-SPI** (role/name/text/states), пиксели — только fallback
  (canvas/игры). Это приватнее и надёжнее OCR-по-скриншотам.
- Wayland работает: pointer через `org.freedesktop.portal.RemoteDesktop` + `ydotool` (uinput)
  как детерминированный fallback; скриншоты через portal (GNOME Shell DBus / Screenshot).
- **Оконный таргетинг compositor-aware**: Hyprland `hyprctl` (наш WM!), KWin, i3, X11/EWMH.
- `doctor` — JSON-отчёт готовности (платформа, порталы, AT-SPI, окна, ввод).

**Реализация в DSH**
1. Установить бинарь (проверить наличие в nixpkgs при реализации; иначе — пакет-обёртка
   с prebuilt).
2. DSH-тул `desktop`: doctor / list_windows / screenshot / click / type / scroll —
   селекторы по role/name/text; vision-слой для скриншотов — локальная VL-модель.
3. Безопасность: тулы запускаются только по явному вызову агента (никаких фоновых),
   approval на действия, скриншоты не персистятся.

**Риски**: порталы/разрешения Wayland (RemoteDesktop требует user-сессию), ydotool-сервис,
доступность в nixpkgs. **Оценка**: средняя; на Hyprland ожидаемо работает (hyprctl + ydotool).

## 4. vibe-runtime

**Факт** (omp docs/vibe-mode.md): vibe-режим = топ-сессия становится ДИРЕКТОРОМ: её тулы
сужены до read/todo/worker-control; воркеры делают поиск/правки/запуски; директор
верифицирует заявки воркеров чтением файлов. Воркеры persistent, addressable, scoped к
владельцу; `/vibe` переключает режим.

**Вывод**: в DSH это УЖЕ покрыто на уровне воркфлоу + инфраструктуры:
- `vibe-director` воркфлоу (порт ln-режима) — директор + persistent воркеры.
- persistent субагенты + `send_message` = адресуемость и верификация чтением.
- `tools.restrict()` (dsh-tools) = сужение тулов директора (read/todo + subagent-тулы) —
  реализуется в пресете, без нового плагина.

**Рекомендация**: закрыть как «покрыто воркфлоу»; опционально — пресет vibe с restrict.

## 5. autoresearch-runtime

**Факт**: прототип `ab-bench.mjs` работает (пресеты × задачи + pairwise-жюри; демо 3:0).

**Как делать надо (runtime)**
1. Набор задач из реальных сессий: `export-session.mjs` (JSONL → HTML) → выжимка задач,
   плюс вручную поддерживаемый tasks.json.
2. Фоновый прогон: `systemd-run --user` запускает ab-bench на тест-наборе, отчёты копятся
   в каталоге (например `~/.local/share/ab-bench/` или `/zero/ai/ab-reports`).
3. Сравнение пресетов по накопленной статистике (победы, время, длина ответов).
4. Опционально: DSH-тул `ab_bench` (запуск + показ последнего отчёта).

**Оценка**: малая; следующий быстрый шаг — фоновый runner + накопление отчётов.

## Итог: порядок и решения

| Направление | Решение | Оценка |
| --- | --- | --- |
| vibe-runtime | ✅ покрыто (воркфлоу + субагенты); опц. пресет с restrict | малый |
| autoresearch-runtime | сделать: фоновый runner + отчёты поверх ab-bench.mjs | малый |
| browser | сделать: browser-cdp (CDP) + тул + vision (qwen2.5vl:7b) | средний |
| computer | сделать: computer-use-linux (AT-SPI/Hyprland) + тул `desktop` | средний |
| collab | НЕ начинать (локально покрыто; agentchat — чужой стек; relay — проект) | — |

Безопасность везде: явный вызов, approval, allowlist, локальные VL-модели (скриншоты не
покидают хост). Все фичи опираются на свободный GPU/локальные модели — без внешних API.
