# План реализации отложенных фич (lsp / eval / checkpoint / TTSR / и др.)

Полноценный план для реализации в этом репозитории своими силами (без «сильных моделей»). Каждая
фича — отдельный server-плагин по уже обкатанному рецепту; порядок — по ценности/риску.

## 0. Рецепт плагина (эталон — 9 уже сделанных)

Каждый плагин = 4 файла + тест:

- `modules/user/nix-maid/apps/dsh-<name>/package.json` — name/type=module/main=lib/index.js/exports;
- `modules/user/nix-maid/apps/dsh-<name>/lib/index.js` — `export const name` + `apply(ctx)`, при
  использовании сервисов ОБЯЗАТЕЛЬНО `export const inject = [...]` (урок: ctx.tools/ctx.memory);
- `modules/user/nix-maid/apps/dsh-<name>.nix` — ensure-скрипт (копия файлов + insert-строка в
  cordis.patch.yml + dsh-restart), activationScripts, systemd user service (копия dsh-osm.nix);
- `modules/user/nix-maid/apps/default.nix` — добавить `n != "dsh-<name>"` в exclude-список;
- функциональный тест: скопировать lib в `~/.dsh/profiles/web/node_modules/.test/`, запустить node с
  моком `apply({tools:{register}, effect})`, проверить реальный сценарий (как hashline/debug).

Проверка перед коммитом: `node --check`, `nix-instantiate --parse`,
`bash scripts/dev/check-all-syntax.sh`, `just fmt`, pre-commit lint (--no-verify только при чужих
ghost-файлах). Активация:
`rm -rf ~/.dsh/profiles/web/node_modules/dsh-<name> && systemctl --user restart dsh`.

## 1. dsh-lsp — символьная навигация по коду (приоритет №1)

**Цель**: тул `lsp` — rename, references, definition, hover, code actions, diagnostics; позиционные
операции (`file`+`line`+`symbol`), `apply:false` для превью правок.

**Архитектура**: LSP-клиент по stdio (JSON-RPC, Content-Length — как DapClient в dsh-debug, только
серверная инициатива: `initialize` → `initialized` → `textDocument/didOpen`); пул серверов по
языкам; маппинг позиций (строка/колонка ↔ offset); запуск сервера из конфига (язык → команда).

**Ключевые API DSH**: `ctx.tools.register(defineTool({...}))` + `inject: ['tools']`; использовать
exec.agent.session.header.cwd для корня проекта (как в dsh-debug/hashline).

**Шаги**: 1) конфиг адаптеров (rust-analyzer, clangd, pyright, tsserver, gopls — по наличию на
хосте); 2) LSP-клиент (request/response + notifications); 3) тул `lsp` с ops: hover, definition,
references, rename (apply:false|true), code_actions, diagnostics; 4) жизненный цикл (shutdown/exit,
таймауты); 5) тест: открыть реальный файл репо (rust/python), definition/references/rename превью.

**Приёмка**: rename в реальном файле работает с превью и apply; references дают все вызовы; нет
утечки процессов (сервер убивается с плагином). Риски: диалекты LSP, маппинг позиций, память.

## 2. dsh-eval — персистентное ядро Python/Bun

**Цель**: тул `eval` — постоянное ядро: состояние живёт между вызовами и субагентами;
инкрементальные ячейки (imports → define → test → use); reset при крахе; `parallel(thunks)` в
ячейке.

**Архитектура**: долгоживущий процесс (python3 -i / bun -e loop) за плагином; JSON-протокол команд;
реестр ядер (session → ядро), idle-timeout, budget (лимит вывода), reset на crash (если процесс умер
— перезапуск с чистым состоянием и явным сообщением).

**Шаги**: 1) ядро python (stdin/stdout JSON loop); 2) ядро bun (аналог); 3) тул `eval` (код, reset,
parallel в ячейке); 4) реестр + idle-timeout; 5) тест: определить переменную → использовать в
следующем вызове → reset → подтвердить чистоту.

**Приёмка**: состояние переживает вызовы; краш ядра не вешает плагин; лимиты срабатывают. Риски:
изоляция (не давать ядру доступ к секретам сверх необходимости), утечка процессов.

## 3. checkpoint / rewind — откат контекста разведки

**Цель**: `checkpoint` ставит точку перед разведкой; `rewind` откатывает контекст к точке, заменяя
промежуточные вызовы кратким отчётом (экономия токенов).

**Архитектура**: два тула + хранилище снапшотов (session → точка). Сначала ресёрч: как DSH хранит
историю (dsh-session JSONL, события) — где встроить. Минимальная версия (soft rewind): checkpoint
сохраняет краткое резюме разведки; rewind возвращает его как synthetic user-инструкцию «забудь про
промежуточное, работай с этим резюме» — БЕЗ реальной хирургии истории.

**Приёмка**: после rewind агент продолжает по резюме; промежуточные вызовы не перечитываются. Риски:
вмешательство в историю сессии — v1 только мягкий rewind (инструкция).

## 4. TTSR / hindsight — правила на стриме

**Цель**: regex-правила (condition/scope/body) на потоке выводов агента прерывают и инжектят
коррекцию; mental-models — фоновые сводки в промпте.

**Архитектура**: хранилище правил (config rules), хук на `assistant/message` (проверить наличие в
KNOWN_SESSION_EVENT_TYPES или agent/pre-step) + инжекция через agent.steer (как boulder);
mental-models — systemPrompt.section с фоновым текстом (концепт уже в agent-guards.ru.md §9).

**Шаги**: 1) формат правила (YAML: condition regex, scope, body — из omfg-user/TTSR); 2) движок
сопоставления; 3) инжекция; 4) тест: правило на «TODO: fix later» в выводе; 5) mental-models v1 —
статический systemPrompt.section из файла.

**Приёмка**: правило срабатывает и инжектит коррекцию; узкий scope не ловит лишнее; mental-model
виден в промпте как фоновое знание. Риски: где именно DSH даёт хук на стрим — сначала проверить.

## 5. dsh-ast-grep — структурный поиск/правка

**Цель**: тул `ast_grep` поверх бинаря ast-grep (sg из nixpkgs): поиск по AST-паттерну, rewrite
(флаг -r), подсветка, glob-фильтры. Язык один на вызов; `$NAME`-захваты.

**Шаги**: 1) добавить `pkgs.ast-grep` в systemPackages (как vscode-js-debug); 2) тул: search
(JSON-вывод sg), run (rewrite с отключением интерактива), 3) тест: поиск вызова функции в репо,
rewrite превью.

**Приёмка**: паттерн с захватами находит ожидаемые узлы; rewrite не трогает файлы без совпадений.
Риски: флаги sg менялись между версиями — сверить sg --help на целевой версии.

## 6. dsh-hub — супервизируемые долгие процессы

**Цель**: тул `hub` (op:start/list/stop) для REPL, watcher-ов, dev-серверов: процесс живёт между
вызовами, вывод собирается, результат доставляется по завершении/таймауту.

**Архитектура**: реестр процессов (session → {proc, буфер вывода, статус}); op:start (команда, cwd,
async), op:list (статусы), op:stop, op:wait (ждёт завершения/таймаута). Параллельно с dsh jobs, но в
сессии агента и с доступом к буферу.

**Приёмка**: сервер/REPL стартует, переживает несколько вызовов, останавливается без
зомби-процессов. Риски: orphan-процессы при крахе dsh — чистить в ctx.effect shutdown.

## 7. autolearn — авто-подъём SKILL.md — ✅ СДЕЛАНО (воркфлоу .agent/workflows/autolearn.md)

**Цель**: из повторяющихся успешных приёмов автоматически создавать/улучшать SKILL.md (omp learn /
manage_skill). Реализуемо как ВОРКФЛОУ (без плагина): после решения задачи агент сам решает, стоит
ли зафиксировать приём, и создаёт скилл по шаблону.

**Шаги**: 1) шаблон SKILL.md (frontmatter name/description/whenToUse — как в памяти); 2) воркфлоу
autolearn.md: критерии (процедура повторима, решала проблему), путь (.dsh/skills/<name>/SKILL.md),
правила (не трогать user-скиллы, не дублировать); 3) связать с memory-extract.

**Приёмка**: воркфлоу в репо; критерии чёткие. Риски: засорение каталога — лимит на количество.

## 8. export — HTML-шаринг сессий — ✅ СДЕЛАНО (минимальный экспортёр .agent/scripts/export-session.mjs)

**Цель**: команда/плагин экспорта текущей сессии в standalone HTML (как omp export/html). Средний
приоритет; сначала ресёрч: как DSH хранит сессию (JSONL) и есть ли готовый рендер (web-ui).
Минимальная версия: bash-скрипт/команда, собирающая JSONL в HTML с минимальным стилем.

## 9. snapcompact — снапшот-компакция — 🔴 ОТЛОЖЕНО (ресёрч: события компакции есть)

Ресёрч: DSH имеет `compaction/start|end|summary|prune` (KNOWN_SESSION_EVENT_TYPES). Однако
полноценная снапшот-компакция = хирургия истории (как checkpoint/rewind, но на уровне компакции) —
рискованно, требует глубокого вмешательства в dsh-compaction-\*. Безопасного v1 не видно; оставить в
бэклоге до явного запроса.

**Цель**: компакция со снапшотами контекста (omp snapcompact-*). Зависит от устройства компакции DSH
(dsh-compaction-*) — сначала исследование, потом либо патч-плагин, либо отказ (риск поломки сессий).
Приоритет низкий; план: 1) ресёрч dsh-compaction API; 2) прототип снапшот-фрейма в
systemPrompt.section; 3) решение о внедрении.

## 10. stt / tts — ✅ ПОКРЫТО существующим стеком (speech.nix), порт omp НЕ нужен

В репо уже есть полноценный речевой стек (`modules/media/audio/speech.nix`): piper-tts (TTS, :8001),
whisper-cpp Vulkan (STT, :8002), chatterbox-tts (ROCm), cosyvoice/moshi в `/zero/ai/speech/engines`.
Из omp stt/tts релевантна только UX-часть (endpointer, streaming-player) — как справочник, не порт.

**Цель**: ASR (диктовка в сессию) и TTS (озвучка ответов) с русскими моделями — релевантно речевому
требованию. Инфраструктуру omp (src/stt, src/tts: worker, endpointer, streaming-player, vocalizer)
брать за образец, но реализовывать отдельно на sherpa-onnx (nixpkgs). План: 1) проверить sherpa-onnx
в nixpkgs; 2) прототип CLI (wav → текст; текст → wav) вне DSH; 3) плагин: тулы stt/tts или
интеграция в web-клиент; 4) русские модели (загрузка, лицензии). Приоритет: средний (после
lsp/eval).

## 11-13. collab / autoresearch / browser / computer

- collab (live-сессии, relay, AES): высочайшая сложность, ниша — НЕ начинать без явного запроса;
  если когда-то — отдельный проект, не плагин.
- autoresearch (A/B стенд промптов): отдельный инструмент; прототип можно как скрипт поверх dsh
  (гонять два пресета на тест-наборе, сравнивать), потом CLI.
- browser (Chromium/puppeteer) и computer (рабочий стол): высокая сложность + безопасность; в
  бэклоге без плана до явного решения.

## Порядок выполнения (рекомендуемый)

1. dsh-lsp (максимальная польза) → 2. dsh-eval → 3. TTSR (сначала ресёрч хука на стрим) → 4. dsh-hub
   → 5. dsh-ast-grep (быстрый, ждёт rebuild для sg) → 6. checkpoint/rewind (soft) → 7. autolearn
   (воркфлоу) → 8. export → 9. stt/tts → 10. snapcompact (после ресёрча).

Каждая фича — отдельный коммит `[dev/ai] Add dsh-<name> ...` с функциональным тестом.

## Закрытые дыры (дополнения к портам)

- **dsh-debug `custom_request`** — сырые DAP-запросы (`command` + `arguments`) через активную
  сессию; тест: `custom_request threads` вернул реальные потоки gdb. Коммит `8f08714b`.
- **dsh-ttsr mental-models** — фоновое знание (`config.mentalModel` или `lib/mental-model.md`)
  инжектится ОДИН раз на сессию как `<mental-model>`-нота (не команда). Тест: первая инъекция есть,
  вторая — нет. Коммит `8f08714b`.

## Остались НЕзакрытыми (честно, с причинами)

- **advisor-рантайм** (peer-shadow надзиратель) — нужен LLM-доступ из плагина (нет в DSH); только
  док.
- **mid-stream TTSR** — DSH не даёт плагину прерывать поток LLM; наша версия инжектит между шагами.
- ~~hashline теги во встроенном `read`~~ — **ЗАКРЫТО (phase 2)**: плагин `dsh-read-tags`
  через `tools/post-execute` переписывает content встроенного `read` в `N#ID| text` (хэш
  идентичен dsh-hashline, проверено 4/4), без форка `dsh-tool-fs`; композиция со
  spill-policy сохранена (listener не prepend).
- ~~eval bun `let`/`const`~~ — **ЗАКРЫТО**: на bun 1.3.13 и node v24 top-level `let`/`const`/
  `class` персистят между вызовами ядра (проверено: `a=42`, `c=10`, `P=7`); повторное
  `let a = ...` → SyntaxError, как в REPL.
- ~~LLM-шаг memory-extractor~~ — **ЗАКРЫТО**: плагин дергает ЛОКАЛЬНЫЙ Ollama
  (`http://127.0.0.1:11434/api/chat`) на session/end-seed/compaction/end; JSON по
  memory-extract.md пишется как `[extract]`, при сбое/нет сигнала — fallback на
  `[draft-extract]`. Конфиг `{endpoint, model, timeoutMs, enabled}`; модель переключается
  в patch-row config плагина (`cordis.patch.yml` → `config.model`).
  **Бенч 2026-08-20 (odin, RX 9070 XT 16GB)**: `qwen3:8b-q8_0` 26s/52 tok/s — дефолт;
  `gemma4:12b` 47s; `deepseek-r1-distill-qwen:14b` 48s; `qwen3dot5:latest` 6s, но
  зацикливается/не JSON — снят с дефолта; `qwen3.5:27b` не влезает в 16GB VRAM (>300s).
- **collab / autoresearch / vibe-рантайм / computer / browser / hub-peer-IRC** — в бэклоге
  (объём/безопасность).
