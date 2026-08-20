# Порт hermes-agent (Nous Research) и других похожих проектов → DSH

Исследование **NousResearch/hermes-agent** (MIT) и сверка с уже портированным из omp /
oh-my-opencode. Что нового даёт hermes, что уже покрыто, что переносить. Источник — локальный клон
`/tmp/hermes-agent` (commit 27562ad, ~190 MB) + hermes-agent.nousresearch.com.

## Что такое hermes-agent

Персональный AI-агент, который гоняет одно ядро поверх CLI, мессенджер-шлюза (Telegram, Discord,
Slack и ~20 платформ), TUI и Electron-desktop. Расширяется **плагинами и скиллами**, не ростом ядра.
Две проектные аксиомы (из AGENTS.md):

- **Per-conversation prompt caching is sacred** — кеш префикса переживает всю сессию; любая мутация
  прошлого контекста или пересборка system prompt на середине сессии ломает кеш и умножает
  стоимость. Единственное исключение — context compression.
- **Core = narrow waist** — каждый core-тул отправляется в каждом вызове API, поэтому бар для нового
  core-тула высок; новая возможность — это CLI-команда + скилл, сервис-гейтед тул или плагин.

## Что нового (не покрыто omp/omo-портами)

### 1. Micro-compaction — непрерывная амортизированная компакция (docs/micro-compaction.md)

Самая ценная находка. Обычная компакция — батч: пересёк порог → сессия останавливается, середина
суммаризуется одним вызовом, большая пауза и один большой счёт. Micro-compaction платит тот же счёт
**частями**: после каждого завершённого хода сворачивается **один старейший непоглощённый обмен**
(assistant+tools, вплоть до следующего user-сообщения) в бегущее резюме.

Ключевые свойства:

- **Сообщения пользователя никогда не компактятся** — ход начинается с assistant-сообщения, идёт
  мимо user-сообщений; инструкции пользователя остаются вербатим на всю сессию. Рациональность:
  нарратив ассистента («прочитал файл, выполнил команду») переживает суммаризацию, а интент
  пользователя — нет.
- Полный ход (а не отдельный тул-результат) сохраняет валидную смену ролей: маркер резюме —
  assistant-роль, ход ограничен user-сообщениями с обеих сторон.
- **Defrag**: когда бегущее резюме превышает порог (`micro_compact_defrag_threshold_tokens`, дефолт
  2000), оно пере-суммаризуется вместо бесконечного роста.
- Конфиг: `micro_compact: true`, `micro_compact_every_n_turns: 1|5|…` (частота пауз кеша), порог
  defrag. Опт-ин, потому что каждый проход ломает префикс-кеш один раз.
- Сбой суммаризатора: транскрипт не трогается, счётчик ошибок; **3 фейла подряд → курсор уходит
  дальше** (иначе один плохой обмен ретраится вечно); пропущенное подхватит следующий батч.
- Оценки: малая быстрая не-reasoning instruct-модель (7B MLX ~31s на проход) лучше большой
  reasoning-модели для суммаризации.
- Метрики: не экономия токенов, а (1) пауза амортизирована, (2) контекст живёт дольше (occupancy
  держится низко вместо пилы до порога).

**Порт в DSH**: это готовый дизайн для отложенного `preemptive-compaction`
(agent-harness-features.ru.md). Оформлено отдельным документом `agent-micro-compaction.ru.md` с
механикой для DSH-плагина (хук на завершение хода, реестр «непоглощённых» обменов, локальная модель
для суммаризации — qwen3:8b уже стоит).

### 2. Prompt assembly: три тира + кеш-стабильность (website/docs/developer-guide/prompt-assembly.md)

System prompt собирается из трёх тиров в строгом порядке (stable → context → volatile):

1. **stable** — идентичность (SOUL.md), тул/модель-гайданс, skills prompt, окружение/платформа;
1. **context** — caller-supplied system_message + проектные контекст-файлы (`.hermes.md` /
   `HERMES.md` / `AGENTS.md` / `CLAUDE.md` / `.cursorrules`);
1. **volatile** — MEMORY.md-снапшот, USER.md-снапшот, внешний memory-провайдер, timestamp.

Эфемерные добавки (HERMES_EPHEMERAL_SYSTEM_PROMPT, prefill) **не входят в кешируемый префикс**.
Правило для разработчиков: не редактировать prompt_builder.py, а менять входы — SOUL.md, MEMORY.md,
проектные файлы, скиллы.

**Порт в DSH**: принцип «стабильный префикс + волатильный хвост» и «правила через файлы, а не через
правку плагина» — зафиксировать в AGENTS.md/доке как дизайн-принцип (у нас уже есть
dsh-rules-injector и dsh-memory-extractor — они ложатся на тиры 2–3 без мутации префикса).

### 3. Memory tool: MEMORY.md + USER.md (tools/memory_tool.py)

Две bounded-папки: **MEMORY.md** (заметки агента: факты окружения, конвенции, тул-квирки) и
**USER.md** (что агент знает о пользователе: предпочтения, стиль, ожидания). Дизайн:

- Оба файла инжектятся в system prompt **замороженным снапшотом** на старте сессии.
- Mid-session записи пишутся на диск сразу (durable), но **не меняют system prompt** — префикс-кеш
  сохраняется; снапшот обновится в следующей сессии.
- Разделитель записей — §; записи могут быть многострочными; лимиты в символах (не токенах).
- Один тул `memory` с action add/replace/remove; replace/remove по короткому уникальному сабстрингу.
- Поведенческий гайданс живёт в schema description тула, не в промпте.

**Порт в DSH**: всё это **уже реализовано** как dsh-memento (user/agent-треки, слои, сабстринг-матч,
бюджеты, замороженный снапшот на старте сессии) + dsh-memory-extractor. Отметить паритет в доке —
hermes подтверждает выбор дизайна. Новое: идея «USER.md как отдельный трек» уже есть; разделитель §
и лимиты-в-символах — деталь реализации, можно перенять в плагин memento.

### 4. Todo tool: caps + re-injection после компакции (tools/todo_tool.py)

Один тул `todo` с параметром `todos` (передать — записать, опустить — прочитать), каждый вызов
возвращает полный список. Капсы: MAX_TODO_CONTENT_CHARS=4000 на элемент, MAX_TODO_ITEMS=256;
результат тула ≤512 KB. Список **пере-инжектится после context compression** (стабильный заголовок,
чтобы отличать синтетическую строку от реальной). Без мутации system prompt.

**Порт в DSH**: todo_write уже есть; перенять капсы (4000 символов на элемент) и пере-инжекцию после
компакции (у нас есть dsh-compaction-todo-preserver — сверить с hermes-подходом «todo хранится в
сообщении, а не в стейте»).

### 5. Скиллы: контракт SKILL.md (skills/ + hermes-agent-skill-authoring)

82 SKILL.md в репо. Формат frontmatter (жёсткие правила валидатора):

- `name` — lowercase-hyphens, ≤64 символа (MAX_NAME_LENGTH);
- `description` — **≤60 символов**, одна фраза, без маркетинговых слов (powerful/comprehensive/…),
  capability statement; системный индекс скиллов обрезает на 57 символах + «...» — триггер должен
  влезать в это окно; при `:` внутри — кавычки, иначе YAML ломается;
- `version` — semver, новые скиллы с 0.1.0;
- `author`, `license`, `platforms: [linux, macos, windows]`;
- `metadata.hermes.tags` + `related_skills`.

**Порт в DSH**: контракт авторинга скиллов — в `agent-skill-authoring.ru.md` (у нас скиллы уже есть
в сессии; единый формат описаний ≤60 символов улучшит discoverability).

### 6. Скиллы-«железные законы» (obra/superpowers адаптации)

- **systematic-debugging**: Iron Law — `NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST`; Feedback
  Loop Rule — до чтения кода создать/найти **тугой** цикл (команда, которая красная на симптоме и
  зелёная на фиксе), а не «не падает». → порт как `.agent/workflows/debugging.md`.
- **test-driven-development**: Iron Law — `NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST`;
  RED-GREEN-REFACTOR; «если не видел тест красным — не знаешь, что он тестирует то». Исключения
  (прототипы, генерированный код, конфиги) — только спросив пользователя.
- **requesting-code-review**: пре-коммит конвейер — diff → security scan → quality gates →
  независимый reviewer-субагент → auto-fix цикл; принцип «No agent should verify its own work». У
  нас есть code-review.mjs + security-scan workflow; перенять шаг «независимый ревьюер».
- **simplify-code**: параллельная чистка 4 ревьюерами (reuse / quality / efficiency / altitude),
  одна задержка вместо четырёх. → расширение code-review.mjs.
- **spike**: одноразовые эксперименты для валидации идеи до продакшена; disposable by design. → порт
  как `.agent/workflows/spike.md`.
- **plan**: план в markdown-файл `.hermes/plans/YYYY-MM-DD_HHMMSS-<slug>.md`, никакого исполнения;
  read-only инспекция разрешена. У нас есть plan-before-code.md — паритет.
- **session-librarian**: организация библиотеки сессий по промптам (find/rename/archive/prune),
  «сначала показать план, потом трогать». → идея для DSH (у нас recall + export-session.mjs).
- **dogfood**: систематический QA веб-приложений через browser-тулсет с доказательствами. → ложится
  на dsh-browser/desktop (AGENTS.md «desktop over CDP» уже есть).

### 7. Инженерные уроки

- **Context switch guard** (hermes_cli/context_switch_guard.py): предупреждение при переключении
  модели внутри сессии на заметно меньший контекст — следующий ход вызовет preflight-компакцию. →
  идея для dsh-mode / хука на model switch.
- **Bounded response reads** (agent/bounded_response.py): чтение тела ошибки стримингового ответа с
  байт-капом и **жёстким wall-clock дедлайном через daemon-поток** (httpx-чтение блокируется внутри
  C-сокета; проверка между чанками не прерывает зависший сервер). → урок для любых сетевых тулов
  DSH.
- **Kanban multi-gateway** (docs/kanban/multi-gateway.md): single-dispatcher posture — только одна
  гейтвея владеет диспетчером, атомарный claim событий против гонок воркеров. → крупная фича, не
  переносим сейчас (нет шлюза-агрегатора в DSH).
- **Cron jobs** (cron/jobs.py): jobs.json + output/{job_id}/{ts}.md, кросс-процессный advisory lock
  (fcntl/msvcrt). → у нас systemd-таймеры покрывают; частичный паритет.

## Сверка с omp/omo-портами (что уже есть, не дублировать)

| Идея hermes                                        | Уже в репо                                           |
| -------------------------------------------------- | ---------------------------------------------------- |
| MEMORY.md/USER.md, замороженный снапшот, сабстринг | dsh-memento + agent-memory-pipeline.ru.md            |
| Memory extract → consolidate                       | dsh-memory-extractor + .agent/prompts/memory-\*.md   |
| Todo re-injection после компакции                  | dsh-compaction-todo-preserver                        |
| Plan-скилл                                         | plan-before-code.md                                  |
| Правила через проектные файлы                      | dsh-rules-injector                                   |
| Скиллы/категории                                   | dsh-category-skill-reminder + agent-categories.ru.md |
| Code review до коммита                             | code-review.mjs + security-scan workflow             |
| Делегирование субагентам                           | delegate-task.md                                     |
| «Desktop over CDP»                                 | AGENTS.md (Automation) + dsh-desktop                 |
| Вредные/повторяющиеся паттерны                     | agent-guards.ru.md (9 гардов)                        |

## Что переносим (этот заход)

1. `docs/howto/agent-port-hermes.ru.md` — этот документ (карта).
1. `docs/howto/agent-micro-compaction.ru.md` — дизайн micro-compaction для DSH (закрывает
   preemptive-compaction из бэклога).
1. `.agent/workflows/debugging.md` — Iron Law дебага (systematic-debugging).
1. `.agent/workflows/spike.md` — одноразовые эксперименты.
1. `docs/howto/agent-skill-authoring.ru.md` — контракт SKILL.md.
1. Обновления: index.md, agent-harness-features.ru.md (статус preemptive-compaction), AGENTS.md
   (правило «сначала root cause»).

## Осталось недочитанным (честно)

- Полные тексты всех 82 скиллов (прочитаны ключевые 10 + authoring-контракт).
- hermes kanban/cron/dashboard internals (крупные фичи, не переносятся сейчас — не добирал).
- Документация gateway/session (~18k строк run.py) — для портов не нужна.
- omp modes/\*, ~50 файлов system/ и ~45 tools/ — зафиксировано ранее в agent-port-research.ru.md.
