# dsh-widgets — виджеты в dsh (JSON-дерево + карточки агентов)

Плагин `dsh-widgets` добавляет в DeepSeek Harness (web-профиль) виджеты общего назначения: инструмент
`json` с раскрывающимся подсвеченным деревом прямо в чате, плюс читабельные карточки для
оркестрационных инструментов (`subagent`, `workflow`, `ralph`, `goal`, `jobs`, `list_agents`), которые
иначе падают в generic-строку «Tool call» с сырым JSON.

## Что добавлено

| Инструмент(ы)             | Карточка                                                                 |
| ------------------------- | ------------------------------------------------------------------------ |
| `json`                    | раскрывающееся дерево с подсветкой типов, поиском, копированием, кнопками «развернуть/свернуть всё», счётчиками узлов/глубины/размера |
| `subagent`, `subagent_fork` | статус (выполняется / готово / фоновая задача / запущен / ошибка), метка из `description`, режим «фон», **полный промпт** (свёрнут по умолчанию: «Показать промпт ▾» + счётчик символов), вывод |
| `workflow`                | имя, «N агентов», разбор `Return value:` и рендер результата тем же JSON-деревом |
| `ralph`                   | статус (готово / блокировка / лимит раундов), «N раундов», summary / evidence / nextSteps / blocker |
| `get_goal`/`create_goal`/`update_goal` | фаза цели, объектив, прогресс «раунды N/M», активация, баннер блокировки |
| `job_output`/`job_list`/`job_kill` | статус задачи (из `[status: …]`), id, вывод |
| `list_agents`             | таблица: id, статус-бейдж, label, parent/depth                            |
| `cordis_inspect_list/query/self` | вывод (`JSON.stringify`) рендерится тем же JSON-деревом                    |
| `plugin_vet`              | бейджи safe/low/medium/high, пакеты с риск-бейджами, score, findings, [REVIEW] |
| `gavel_review`            | лёгкий markdown-рендер отчёта (заголовки/буллеты)                          |
| `memory` / `memory_recall` | записи памяти (`- [track/scope] text`) списком с чипами                    |
| `bash_live`               | команда + **живой терминал**: вывод стримится в узел чата по мере выполнения (паттерн workflow-panel: `session.append("tool/bash-live-*")` → `conversationEvents` → узел `bash-live` с автоскроллом); полный вывод возвращается в результат инструмента |

Плюс два живых DOM-элемента над композером: **activity-стрип** (бегущие субагенты + фоновые задачи +
раунды цели из session-проекций `subagentsByParent` / `jobsBySession` / `goal`, обновляется по
подписке) и чип **«раунды N/M»** прямо в GoalBar (завершённая цель/блокировка — баннером).

В activity-стрип также живёт **индикатор «что идёт в bash»**: пока bash-вызов выполняется, в стрипе
тикает `bash: <первая строка команды> · Nс` (команда берётся из chat-проекции по `data-chat-call-id`,
таймер — по первому наблюдению вызова). Стриминга вывода в этой версии dsh нет (на проводе только
`tool/call` → `tool/result`), поэтому живой показ ограничен командой + временем выполнения; сам вывод
появляется в карточке при завершении (auto-expand + без обрезки — правки `dsh-gui-tweaks`).

Неверный JSON — это **карточка ошибки** (со строкой/столбцом), а не упавший вызов. Очень большой JSON
обрезается на сервере с баннером «показан фрагмент». В TUI/headless работает текстовая сводка
(деградация по замыслу).

## Уведомления о завершении субагентов (фикс «Unknown content block»)

Когда фоновый субагент завершается (упал / закончился / отказ / готов), родительская сессия получает
сообщение с `source.kind = "subagent-settled`. Стоковый UI проецирует его как context-строку, а все
нетекстовые блоки финального сообщения ребёнка (`reasoning`, `tool-call`) рендерит как
**«Unknown content block»** с сырым JSON. Слота для этого нет, поэтому плагин делает DOM-трансформу:

- находит строку уведомления по `data-chat-flow-key` (ключ берётся из живой проекции `chat` —
  того же стора, из которого рендерится чат);
- строит карточку: бейдж причины (упал / завершён / остановлен / лимит токенов / отказ / оборван),
  короткий id ребёнка, сводка, «Заключительное сообщение» — текст + раскрывающиеся «Размышления»
  (открыты по умолчанию для коротких) и «🛠 tool-call» / «Результат вызова»;
- вставляет карточку перед строкой и прячет строку (React её не видит; при пересоздании строки
  MutationObserver повторно применяет трансформу).

Данные читаются из проекции, а не из DOM-дампов, поэтому обрезки нет. Весь текст — через
`textContent` (блоки — вывод модели, недоверенные).

## Как устроены виджеты в dsh (итог исследования)

- dsh — «всё есть плагин» (cordis). Виджет = **инструмент** (сервер) + **keyed toolview** (клиент).
- Инструмент в `output.presentationMeta` проецирует дескриптор `{ kind: … }`; он сохраняется в
  `tool/result` meta, поэтому реплей перерисовывает карточку из лога без повторного вызова.
- Клиентский плагин — это `window.__ModuleLoader__.load({ id, factory })`, внутри которого
  `ctx.slots.register({ name: 'tool.call.toolview', key: '<имя инструмента>', priority: -10 }, Component)`.
  Ключ слота — **имя инструмента на проводе** (открытое множество: любой инструмент, включая свой).
- `priority: -10` перекрывает встроенную строку (паттерн `dsh-gui-tweaks`).
- Темы — только переменные `--dsw-alias-*` (border-l1, bg-layer-2/3, label-primary/secondary/tertiary,
  state-success/warn/error/business-primary, …) — светлая/тёмная тема подхватывается автоматически.
- Рендер — только `React.createElement` + текстовые узлы, без `dangerouslySetInnerHTML` (значение JSON
  приходит из вывода модели и считается недоверенным).
- Установка — plain-каталог в `~/.dsh/profiles/web/node_modules/` (без pnpm: симлинк `@deepseek-ai` не
  переживает pnpm-записей) + строка `- insert: [{ id: widgets, name: dsh-widgets }]` в
  `~/.dsh/profiles/web/cordis.patch.yml`.

## Ключевая находка: почему «красиво» не работало из коробки

Оркестрационные инструменты (`subagent`, `workflow`, `ralph`, `goal`, `jobs`) **не задают
`presentationMeta`**, поэтому `block.meta` у них всегда пуст — до клиента доходит только
`block.call.argsRaw` (аргументы) и `block.content` (отрендеренный текст). Generic-строка их просто
выводит как «Tool call» + сырой JSON. Поэтому карточки для них — клиентские, парсят `argsRaw` и
`content` (формат текста стабилен: `started subagent <id>`, `started background subagent task <id>`,
`workflow "<name>" completed (N agents).\nReturn value:\n…` и т.д.).

## Живой вывод bash (`bash_live`) — полностью через плагин

Стоковый `bash` не стримит вывод (на проводе только `tool/call` → `tool/result`). Но плагин может
обойти это без правки ядра: инструмент `bash_live` запускает команду через `ctx.shell.start`
(живой хэндл процесса, инкрементальные `readOutput()` дельты — тот же механизм, что у фоновых
job'ов), а каждый чанк кладёт в сессию через `session.append("tool/bash-live-output", …)` — тот же
durable-канал, которым workflow-инструмент эмитит `tool-workflow/*` для своей панели. Клиент
`dsh-widgets` регистрирует `conversationEvents`-определение (паттерн `dsh-client-ui-workflow-run`):
события `tool/bash-live-start|output|end` фолдятся в узел чата `bash-live` — живой терминал с
автоскроллом, бейджем «Выполняется» и финальным статусом. Реплей-стабильно (узлы фолдятся из лога).

Ограничения: поток событий урезается до ~500 ивентов / 16 КБ на чанк (в лог не сваливается всё —
полный вывод всегда в результате инструмента); для коротких команд обычный `bash` быстрее, поэтому
`bash_live` описан как инструмент для долгих команд (сборки, установки, тесты, логи).

## Серверные патчи dsh (staged, применяются при пересборке dsh)

`packages/dsh/patch-widgets.py` (вызывается в `postInstall` `packages/dsh/default.nix`, exact-string
замены со счётчиком вхождений — при дрейфе версии dsh сборка падает громко):

1. **`model`-параметр инструмента `subagent`** — модель ребёнка переопределяется на каждый вызов
   (`subagent(..., model: "deepseek-v4-flash")`). Провайдер уже резолвит модель как
   `request.agentOptions?.model ?? parent.options.model` (dsh-subagent), так что это чистый
   pass-through. Проверено функционально: `agentOptions` в запросе к провайдеру = `{ model }`.
2. **`presentationMeta` на `subagent` / `workflow` / `ralph`** — в `tool/result` meta кладётся
   дескриптор `{ kind: "subagent"|"workflow"|"ralph", … }` (структурированные поля вместо парсинга
   текста; карточки сегодня всё равно парсят текст — мета это путь к закалке и реплей-стабильности).

## Чего не хватало (список недостающих виджетов)

Инвентаризация 54 model-facing инструментов этого деплоя: 20 имеют keyed toolview (stock:
`bash`/`read`/`edit`/`write`/`rg`/`glob`/`web_search`/`web_fetch`/`todo_write`/`ask_user_question`/
`skill`/`cordis_*`; кастомные: `osm_*` → Leaflet, `visualize` → iframe, `todo_write`/`ask_user_question`
→ карточки `dsh-gui-tweaks`). **33 падали в generic**; из них этим плагином покрыты:
`subagent`, `subagent_fork`, `workflow`, `ralph`, `get_goal`, `create_goal`, `update_goal`,
`job_output`, `job_list`, `job_kill`, `list_agents`, `cordis_inspect_list/query/self`, `plugin_vet`,
`gavel_review`, `memory`, `memory_recall`.

Осталось без карточек:
- Тривиальные ack (смысла в карточке мало): `send_message`, `interrupt_agent`, `report`,
  `exit_plan_mode`, `structured_output`, `schedule_*`.
- Остальное: `pwsh` (терминал — generic уже рендерит terminal-view), `read_image`,
  `str_replace_editor`, `read_document`, `describe_image`, `free_search_test`, `platform_search`,
  `recall`.

## Как активировать и развивать

- Активация: `systemctl --user restart dsh.service` (или следующий `nixos-rebuild switch` — модуль
  `dsh-widgets.nix` ставит плагин через activationScript + systemd-oneshot).
- Код: `modules/user/nix-maid/apps/dsh-widgets/` (сервер `lib/index.js`, инструмент `lib/tools.js`,
  клиент `lib/client.js`).
- Переприменить изменённую версию из модуля: удалить `~/.dsh/profiles/web/node_modules/dsh-widgets` и
  перезапустить dsh (паттерн «копируем только если файла нет» — локальные правки переживают
  пересборку).
- Добавить карточку: в `lib/client.js` — компонент + запись в `KEYED_VIEWS`; для собственного
  инструмента с полноценным `presentationMeta` — смотри `dsh-osm` (карта) как эталон.
