# Agent-промпты: исследование omp и oh-my-opencode — полный обзор

Дополнение к уже портированным кускам (AGENTS.md-секции, docs/howto/agent-guards.ru.md,
.agent/workflows/plan-before-code.md, .agent/workflows/delegate-task.md). Здесь — что добыто в ходе
углублённого исследования и как это меняет план порта.

## Источники

- **omp 17.3.4** — локально: /nix/store/6f6a8cbpqzilf5lv4y6zd0gpkkm5y0mk-omp-17.3.4/share/omp/src
  (прочитаны напрямую: advisor/, memories/, bench/, security/, personalities, base system-prompt,
  subagent-промпты, goal-машина, ~10 tool-контрактов, 9 agent-промптов).
- **oh-my-openagent (oh-my-opencode)** — склонирован: /tmp/omo-repo (52 MB, ветка dev):
  packages/prompts-core/prompts/ (atlas/, prometheus/, ultrawork/, mode/),
  packages/omo-opencode/src/agents/, src/hooks/ (46 хуков), .agents/skills/ + .opencode/skills/
  (SKILL.md), packages/omo-senpi/skills/ulw-plan/.
- **mintlify docs** (канонические md-страницы): /tmp/mintlify-md/ — 20 страниц: все агенты, tools
  (hashline-edit, delegate-task, overview), hooks, skills, tmux, mcps, comment-checker,
  introduction.

## omp — находки сверх уже портированного

### 1. Advisor-паттерн (peer-shadow) — самое недооценённое

advisor/system.md + advise-tool.md + active-repo-watchdog.md: отдельная advisor-модель смотрит
инкрементальный транскрипт агента (включая thoughts) и шлёт ОДНУ короткую конкретную реплику через
advise_tool — только когда что-то реально важно. Что делает:

- оспаривает преждевременное done, тонкую верификацию, пропущенные рассуждения;
- флагует дрейф от запроса пользователя немедленно;
- предотвращает кроличьи норы и запечённые edge-case'ы;
- НЕ повторяет то, что агент уже знает (ошибки типов, LSP-диагностику, упавшие тесты);
- по умолчанию read-only (read/grep/glob), расширяется через WATCHDOG.yml;
- есть секция completeness: сначала проверь, потом поднимай вопрос. Порт: готовый сценарий для
  DSH-субагента «надзиратель» или промпт-блока при длинных задачах.

### 2. Двухстадийная память (extract → consolidate в SKILL.md-плейбуки)

memories/stage_one_system.md: из «раскатки» извлекается строгий JSON — rollout_summary,
rollout_slug, raw_memory; нет durable-сигнала → пустые строки (шум отбрасывается).
memories/consolidation.md: stage-two сливает корпуса в memory_md (долгая память), memory_summary
(подсказка на промпт-тайме) и skills[] (переиспользуемые playbook'и, каждый = skills/<name>/SKILL.md
\+ опционально scripts/templates/examples). memories/read-path.md: память — эвристики и процессный
контекст; текущее состояние репо, вывод рантайма и инструкция пользователя — факты; «память одна
НИКОГДА не доказательство». Порт: прямая аналогия с dsh-memento; формат summary +
playbooks-as-skills стоит перенять.

### 3. Security-конвейер

security/scan-request.md: сканирование = запуск immutable-плана
(repo/kind/revisions/include/exclude, plan-fingerprint) → инвентаризация scope → делегирование
непересекающихся назначений security-reviewer через task → сверка результатов → один
security_publish с findings, честным coverage и финальным отчётом. Порт: образец для связки
gavel/plugin_vet в DSH.

### 4. subagent-system-prompt (omp)

Структура: Role → Context → Plan (assignment wins при конфликте; план НЕ перечитывать с диска) →
Coop (изолированный worktree «никогда не трогай файлы вне дерева», irc-пиры через hub: сначала
спроси владельца файла, короткие сообщения, await только когда реально застрял) → Completion
(никакой todo-наррации и прогресс-апдейтов; только терминальный yield с результатом или
инкрементальные секции type: string[]). Порт: готовый шаблон для субагентов DSH.

### 5. Прочее

- bench/cache-prefix\*.md — namespace для промпт-кэша (узкая тема, не критично).
- modes/ — режимы (print-mode, interactive-mode, ultrathink, turn-budget, loop-limit, ...) —
  детально не читались (см. «Что осталось недочитанным»).

## oh-my-opencode — ключевые находки

### 1. Дисциплинарные агенты и их реальные промпты

- Sisyphus (оркестратор): todo-driven workflow, Intent Gate (классификация намерения),
  стратегическая делегация, параллельное исполнение; после 3 подряд фейлов — смена стратегии,
  документирование попыток; критерий завершения: todos done + lsp_diagnostics чисто
  - сборка проходит + исходный запрос полностью закрыт.
- Hephaestus (deep worker): «Senior Staff Engineer. You do not guess. You verify. You do not stop
  early. You complete.» — цель, а не рецепт.
- Prometheus (планировщик): план-mode sticky («do X» = «plan X»), исполнение — только в отдельной
  worker-сессии через /start-work; вся логика — в скилле ulw-plan.
- ulw-plan skill: explore-first, «ask few sharp questions — or none»; выход = ONE decision-complete
  план, который воркер исполняет без единого уточнения; approval gate (ждёт явного ок); plan-gate:
  metis/momus ревью разрешены только при наличии файла плана с review_required; опциональные
  advisory-лейны architect/ultrabrain (read-only, TASK/ DELIVERABLE/SCOPE/VERIFY/STOP WHEN, «claims
  to verify, not decisions»).
- Metis (gap-анализ до планирования): классификация намерения (refactor/feature/bugfix/unknown)
  определяет стратегию; MUST-списки вида «Define Must NOT Have section (AI over-engineering
  prevention)», «Record all user decisions in Key Decisions», «Flag assumptions explicitly».
- Momus (ревьюер плана): approval bias, блокируют только проверяемые дефекты (файлы существуют,
  задачи не противоречат, QA-сценарии конкретны, ~80% ясно = исполняемо).
- Oracle: read-only консультант по архитектуре/отладке (паттерн AmpCode).
- Atlas (todo-оркестратор): Anti-Duplication Rule, 6-Section Prompt Structure (MANDATORY),
  AUTO-CONTINUE POLICY (strict), Parallel Delegation — DEFAULT, NOT OPTIONAL, verify personally
  после каждой делегации, notepad-система (learnings/decisions/issues/verification/problems),
  Boulder-Complete Nudge.
- Sisyphus-Junior: исполнитель, модель зависит от категории (quick→haiku, deep→codex,
  artistry→gemini и т.д.); не может делегировать; обязан закрыть todos.

### 2. Точный текст boulder-инъекции (todo-continuation-enforcer)

Из hooks/todo-continuation-enforcer/constants.ts (CONTINUATION_PROMPT):

```
[system-directive todo_continuation]
Incomplete tasks remain in your todo list. Continue working on the next pending task.
- Proceed without asking for permission
- Mark each task complete when finished
- Do not stop until all tasks are done
- If you believe all work is already complete, the system is questioning your completion claim.
  Critically re-examine each todo item from a skeptical perspective, verify the work was actually
  done correctly, and update the todo list accordingly.
```

Механика: событие session.idle → обратный отсчёт 2s (toast 900ms, grace 500ms, abort-окно 3s) →
инъекция; экспоненциальный backoff: база 30s, ×2 за фейл, максимум 5 подряд, затем пауза 5 мин;
cooldown 5s; stagnation-detection (max 3). Отдельные guard'ы: compaction-guard (60s), token-limit,
pending-question-detection (не вставлять, когда ждём ответа пользователя), parent-wake-race.

### 3. hashline-edit — фича харнесса, не промпт

Каждая строка при чтении получает {line}#{hash} (CID-алфавит ZPMQVRWSNKTXJBYH, 2 символа); правки
ссылаются на теги; при расхождении хэша правка отклоняется ДО коррупции; есть операции
replace/append/prepend, autocorrect при сдвиге строк, ошибки: hash mismatch, invalid reference,
overlapping ranges. Заявленный эффект (по README): успех правок Grok Code Fast 6.7% → 68.3%.

### 4. Категории и скиллы

- Категории: quick, deep, ultrabrain, artistry, visual-engineering, writing, unspecified-low/high;
  категория → fallback-цепочка моделей; хук category-skill-reminder напоминает загружать скиллы под
  категорию.
- SKILL.md: YAML frontmatter (name, description с триггерами, metadata); 4 уровня discovery (project
  \> opencode > user > builtin); skill-embedded MCP изолируется ключом sessionID:skill:server.
- hyperplan: 5 «враждебных» членов (unspecified-low/high, deep, ultrabrain, artistry) через
  team-mode, кросс-критика, выжившие инсайты → план-агенту; hard preconditions (team-mode включён,
  роль lead).
- security-research: 3 охотника за уязвимостями + 2 PoC-инженера параллельно, severity по
  фактической эксплуатируемости.
- ulw-plan — см. выше; git-master (атомарные коммиты), frontend (design-first UI), playwright
  (браузерная автоматизация) — скиллы-«бандлы» инструкций + MCP.

### 5. Hooks: 46 шт., 3 тира

Core 37 (Session 23 / Tool Guard 10 / Transform 4), Continuation 7 (boulder-сессии, background
tasks), Skill 2 (category-skill-reminder, auto-slash-command). Самые ценные:
todo-continuation-enforcer, atlas (мастер boulder-сессий), compaction-todo-preserver,
rules-injector, preemptive-compaction, edit/json-error-recovery, comment-checker,
notepad-write-guard, plan-format-validator, agent-usage-reminder, keyword-detector,
unstable-agent-babysitter, delegate-task-retry, task-resume-info.

### 6. ultrawork: протоколы гарантии

ABSOLUTE CERTAINTY PROTOCOL, Scenario Contract до имплементации, manual QA и TDD — MANDATORY,
Verification Anti-Patterns (BLOCKING), Reviewer Gate, Durable Notepad (переживает потерю контекста):
Ultrawork Notepad → Plan / Scenarios / Now / Todo / Findings (file:line) / Learnings.

## Ревизия плана порта

Уже портировано (прошлая сессия): evidence-first reasoning, ask default-to-action, todo-контракт,
goal-completion audit, 9 агент-гардов, plan-before-code, delegate-task (7 элементов), категории.

Уточнения к существующему:

- delegate-task.md: в Atlas/Sisyphus официально 6 секций (TASK/EXPECTED OUTCOME/REQUIRED TOOLS/ MUST
  DO/MUST NOT DO/CONTEXT); REQUIRED SKILLS приходит отдельно через load_skills — пометить 7-й
  элемент как опциональный.
- agent-guards.ru.md п.6: заменить пересказ на точный текст omo CONTINUATION_PROMPT + механику
  (backoff 30s×2, max 5, пауза 5 мин; не вставлять при ожидании ответа пользователя).

Новые кандидаты (приоритет):

1. Advisor-паттерн (omp) — «советник поверх агента», 1 короткая реплика, completeness-first.
1. Двухстадийная память extract→consolidate→SKILL.md (omp) — рекомендация для memento.
1. subagent-шаблон omp (Role/Context/Plan/Coop/Completion + yield-протокол).
1. ulw-plan: decision-complete план + approval gate + plan-gate для ревьюеров — усилить
   plan-before-code.md.
1. Atlas: anti-duplication, parallel delegation default, verify personally.
1. Security-конвейер (omp scan-coordinator → reviewer → publish).
1. hashline-edit — зафиксировать как фичу харнесса (не промпт), отдельным ресёрчем.
1. Маленькие хуки-идеи: category-skill-reminder, agent-usage-reminder, compaction-todo-preserver.

## Что осталось недочитанным (честно)

- omp modes/\* в деталях; ~50 файлов system/ и ~45 tools/ omp (списки получены; субагенты,
  запущенные для конденсации, статус ready без доставленных отчётов — материал добирался напрямую).
- Полные тексты atlas/default.md (497 стр.), ultrawork/default.md (339), тела промптов
  metis/momus/oracle/explore/librarian из TS (извлечены ключевые фрагменты, не всё).
- docs/guide/agent-model-matching.md, docs/guide/team-mode.md (переданы субагенту; ключевые идеи
  покрыты из orchestration.md и mintlify).
