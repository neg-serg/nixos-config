# dsh-widgets — виджеты в dsh (JSON-дерево + карточки агентов)

Плагин `dsh-widgets` добавляет в DeepSeek Harness (web-профиль) виджеты общего назначения:
инструмент `json` с раскрывающимся подсвеченным деревом прямо в чате, плюс читабельные карточки для
оркестрационных инструментов (`subagent`, `workflow`, `ralph`, `goal`, `jobs`, `list_agents`),
которые иначе падают в generic-строку «Tool call» с сырым JSON.

## Что добавлено

| Инструмент(ы)                          | Карточка                                                                                                                                                                                                                                                                                                                                               |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `json`                                 | раскрывающееся дерево с подсветкой типов, поиском, копированием, кнопками «развернуть/свернуть всё», счётчиками узлов/глубины/размера                                                                                                                                                                                                                  |
| `subagent`, `subagent_fork`            | статус (выполняется / готово / фоновая задача / запущен / ошибка), метка из `description`, режим «фон», **полный промпт** (свёрнут по умолчанию: «Показать промпт ▾» + счётчик символов), вывод                                                                                                                                                        |
| `workflow`                             | имя, «N агентов», разбор `Return value:` и рендер результата тем же JSON-деревом                                                                                                                                                                                                                                                                       |
| `ralph`                                | статус (готово / блокировка / лимит раундов), «N раундов», summary / evidence / nextSteps / blocker                                                                                                                                                                                                                                                    |
| `get_goal`/`create_goal`/`update_goal` | фаза цели, объектив, прогресс «раунды N/M», активация, баннер блокировки                                                                                                                                                                                                                                                                               |
| `job_output`/`job_list`/`job_kill`     | статус задачи (из `[status: …]`), id, вывод                                                                                                                                                                                                                                                                                                            |
| `list_agents`                          | таблица: id, статус-бейдж, label, parent/depth                                                                                                                                                                                                                                                                                                         |
| `cordis_inspect_list/query/self`       | вывод (`JSON.stringify`) рендерится тем же JSON-деревом                                                                                                                                                                                                                                                                                                |
| `plugin_vet`                           | бейджи safe/low/medium/high, пакеты с риск-бейджами, score, findings, [REVIEW]                                                                                                                                                                                                                                                                         |
| `gavel_review`                         | лёгкий markdown-рендер отчёта (заголовки/буллеты)                                                                                                                                                                                                                                                                                                      |
| `memory` / `memory_recall`             | записи памяти (`- [track/scope] text`) списком с чипами                                                                                                                                                                                                                                                                                                |
| `bash_live` (опционально)              | команда + **живой терминал**: вывод стримится в узел чата по мере выполнения (паттерн workflow-panel: `session.append("tool/bash-live-*")` → `conversationEvents` → узел `bash-live` с автоскроллом); полный вывод возвращается в результат инструмента. Регистрируется только при `enableBashLive: true` в конфиге деплоя (**по умолчанию выключен**) |

Плюс два живых DOM-элемента над композером: **activity-стрип** (бегущие субагенты + фоновые задачи +
раунды цели из session-проекций `subagentsByParent` / `jobsBySession` / `goal`, обновляется по
подписке) и чип **«раунды N/M»** прямо в GoalBar (завершённая цель/блокировка — баннером).

В activity-стрип также живёт **индикатор «что идёт в bash»**: пока bash-вызов выполняется, в стрипе
тикает `bash: <первая строка команды> · Nс` (команда берётся из chat-проекции по
`data-chat-call-id`, таймер — по первому наблюдению вызова). Стриминга вывода в этой версии dsh нет
(на проводе только `tool/call` → `tool/result`), поэтому живой показ ограничен командой + временем
выполнения; сам вывод появляется в карточке при завершении (auto-expand + без обрезки — правки
`dsh-gui-tweaks`).

Неверный JSON — это **карточка ошибки** (со строкой/столбцом), а не упавший вызов. Очень большой
JSON обрезается на сервере с баннером «показан фрагмент». В TUI/headless работает текстовая сводка
(деградация по замыслу).

## Уведомления о завершении субагентов (фикс «Unknown content block»)

Когда фоновый субагент завершается (упал / закончился / отказ / готов), родительская сессия получает
сообщение с `source.kind = "subagent-settled`. Стоковый UI проецирует его как context-строку, а все
нетекстовые блоки финального сообщения ребёнка (`reasoning`, `tool-call`) рендерит как **«Unknown
content block»** с сырым JSON. Слота для этого нет, поэтому плагин делает DOM-трансформу:

- находит строку уведомления по `data-chat-flow-key` (ключ берётся из живой проекции `chat` — того
  же стора, из которого рендерится чат);
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
- Темы — только переменные `--dsw-alias-*` (border-l1, bg-layer-2/3,
  label-primary/secondary/tertiary, state-success/warn/error/business-primary, …) — светлая/тёмная
  тема подхватывается автоматически.
- Рендер — только `React.createElement` + текстовые узлы, без `dangerouslySetInnerHTML` (значение
  JSON приходит из вывода модели и считается недоверенным).
- Установка — plain-каталог в `~/.dsh/profiles/web/node_modules/` (без pnpm: симлинк `@deepseek-ai`
  не переживает pnpm-записей) + строка `- insert: [{ id: widgets, name: dsh-widgets }]` в
  `~/.dsh/profiles/web/cordis.patch.yml`.

## Ключевая находка: почему «красиво» не работало из коробки

Оркестрационные инструменты (`subagent`, `workflow`, `ralph`, `goal`, `jobs`) **не задают
`presentationMeta`**, поэтому `block.meta` у них всегда пуст — до клиента доходит только
`block.call.argsRaw` (аргументы) и `block.content` (отрендеренный текст). Generic-строка их просто
выводит как «Tool call» + сырой JSON. Поэтому карточки для них — клиентские, парсят `argsRaw` и
`content` (формат текста стабилен: `started subagent <id>`, `started background subagent task <id>`,
`workflow "<name>" completed (N agents).\nReturn value:\n…` и т.д.).

## Живой вывод bash (`bash_live`) — полностью через плагин, off by default

> **Статус:** инструмент выключен по умолчанию (флаг `enableBashLive` в конфиге деплоя
> `dsh-widgets`, `false` дефолт) — на практике с ним было больше проблем, чем пользы.
> **Сейчас `bash_live` считается сломанным: не включать и не использовать** (см. «Задача»
> ниже). Чтобы включить обратно без правки кода, выставьте `enableBashLive: true` в
> deployment-конфиге плагина и перезапустите `dsh.service` — но только после того, как
> задача починки закрыта.

Стоковый `bash` не стримит вывод (на проводе только `tool/call` → `tool/result`). Но плагин может
обойти это без правки ядра: инструмент `bash_live` запускает команду через `ctx.shell.start` (живой
хэндл процесса, инкрементальные `readOutput()` дельты — тот же механизм, что у фоновых job'ов), а
каждый чанк кладёт в сессию через `session.append("tool/bash-live-output", …)` — тот же
durable-канал, которым workflow-инструмент эмитит `tool-workflow/*` для своей панели. Клиент
`dsh-widgets` регистрирует `conversationEvents`-определение (паттерн `dsh-client-ui-workflow-run`):
события `tool/bash-live-start|output|end` фолдятся в узел чата `bash-live` — живой терминал с
автоскроллом, бейджем «Выполняется» и финальным статусом. Реплей-стабильно (узлы фолдятся из лога).

Ограничения: поток событий урезается до ~500 ивентов / 16 КБ на чанк (в лог не сваливается всё —
полный вывод всегда в результате инструмента); для коротких команд обычный `bash` быстрее, поэтому
`bash_live` описан как инструмент для долгих команд (сборки, установки, тесты, логи).

Контракт персистентности: типы `tool/bash-live-*` — вне словаря `KNOWN_SESSION_EVENT_TYPES` текущего
harness (rc.6), а `Session.append()` не умеет ставить маркер `ignorable` на событие (конверт
собирается как `{ type, seq, time, data, surfaceOp?, sourceEventSeqs? }` — опции `ignorable` нет).
Ридер истории отказывается открывать лог с неизвестным не-ignorable событием
(`SessionFormatUnsupportedError` → сессия выглядит «сдохшей»: не открывается, агент недоступен).

Регистрация трёх типов в общем сете (`KNOWN_SESSION_EVENT_TYPES.add(type)` в `tools.js` при
загрузке плагина) **на практике не защищает**: плагин и `dsh-session-persistence` грузят разные
инстансы `@deepseek-ai/dsh-session` (профильные `node_modules` против harness), поэтому добавление
в сет не доходит до ридера, и каждый запуск `bash_live` снова пишет не-ignorable события.
19.08.2026 от этого умерли три сессии (`session-1a5d8a15…`, `session-e8d372df…`,
`session-f6daf551…`); отремонтированы вручную — событиям проставлен `"ignorable": true`
(бэкапы — в `~/.dsh/repair-backups/bash-live-ignorable/`). После этого `dsh-selfheal` научили
чинить такие логи автоматически (см. «Задача», п. 3) — ручной ремонт больше не нужен.

## Задача (TODO): починить `bash_live` по-настоящему

Владелец задачи — сессия «Превью картинок в dsh-web» (плагин `dsh-preview`; задача назначена
ей, промпт юзер отправляет сам). Пока задача не закрыта, `bash_live` **не использовать** — ни в
этой сессии, ни в субагентах, иначе они снова застрянут/умрут.

Что нужно сделать (любой из вариантов, лучше первый в связке с третьим):

1. **Научиться ставить `ignorable: true` на события.** `Session.append(type, data)` не принимает
   флаг — нужно либо дождаться/продавить отложенную harness'ом поверхность регистрации
   плагин-событий (см. комментарий в `dsh-session` у `KNOWN_SESSION_EVENT_TYPES`), либо патчить
   `dsh-session` (`packages/dsh/patch-widgets.py` уже шьёт серверные патчи), чтобы
   `append` принимал опцию `{ ignorable: true }` и плагин проставлял её для `tool/bash-live-*`.
2. **Либо** выпилить `bash_live` совсем (клиентская карточка + серверный инструмент + флаг
   `enableBashLive`) и оставить живой показ bash только через activity-стрип (команда + таймер).
3. ✅ **Сделано (19.08.2026):** `dsh-selfheal` теперь авточинит такие логи — семантический
   фикс «`tool/bash-live-*` без `ignorable` → проставить `ignorable: true`» добавлен в
   `validateEvent` / `validateAndFixLines` (fork-чекаут
   `~/src/1st-level/@projects/dsh-web-ui/packages/dsh-selfheal/lib/repair-core.mjs`; модуль
   `modules/user/nix-maid/apps/dsh-selfheal.nix`). Применяется при следующем рестарте dsh;
   семантический проход чинит файлы через ~3 с после старта и далее каждые 15 мин
   (в отчёте/логе selfheal теперь видно «semantic: N event(s) repaired (bash-live ignorable)»).
   Пункты 1–2 (настоящая починка `bash_live`) остаются открытыми.

Как воспроизводится/проверяется: включить `enableBashLive: true`, запустить в сессии
`bash_live` с длинной командой, убедиться, что в `session.jsonl.zstd` события
`tool/bash-live-*` пишутся с `"ignorable": true` (или типы реально попадают в сет ридера), и что
сессия открывается/перезагружается без `SessionFormatUnsupportedError`.

## Серверные патчи dsh (staged, применяются при пересборке dsh)

`packages/dsh/patch-widgets.py` (вызывается в `postInstall` `packages/dsh/default.nix`, exact-string
замены со счётчиком вхождений — при дрейфе версии dsh сборка падает громко):

1. **`model`-параметр инструмента `subagent`** — модель ребёнка переопределяется на каждый вызов
   (`subagent(..., model: "deepseek-v4-flash")`). Провайдер уже резолвит модель как
   `request.agentOptions?.model ?? parent.options.model` (dsh-subagent), так что это чистый
   pass-through. Проверено функционально: `agentOptions` в запросе к провайдеру = `{ model }`.
1. **`presentationMeta` на `subagent` / `workflow` / `ralph`** — в `tool/result` meta кладётся
   дескриптор `{ kind: "subagent"|"workflow"|"ralph", … }` (структурированные поля вместо парсинга
   текста; карточки сегодня всё равно парсят текст — мета это путь к закалке и реплей-стабильности).

## Чего не хватало (список недостающих виджетов)

Инвентаризация 54 model-facing инструментов этого деплоя: 20 имеют keyed toolview (stock:
`bash`/`read`/`edit`/`write`/`rg`/`glob`/`web_search`/`web_fetch`/`todo_write`/`ask_user_question`/
`skill`/`cordis_*`; кастомные: `osm_*` → Leaflet, `visualize` → iframe,
`todo_write`/`ask_user_question` → карточки `dsh-gui-tweaks`). **33 падали в generic**; из них этим
плагином покрыты: `subagent`, `subagent_fork`, `workflow`, `ralph`, `get_goal`, `create_goal`,
`update_goal`, `job_output`, `job_list`, `job_kill`, `list_agents`,
`cordis_inspect_list/query/self`, `plugin_vet`, `gavel_review`, `memory`, `memory_recall`.

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
- Переприменить изменённую версию из модуля: удалить `~/.dsh/profiles/web/node_modules/dsh-widgets`
  и перезапустить dsh (паттерн «копируем только если файла нет» — локальные правки переживают
  пересборку).
- Добавить карточку: в `lib/client.js` — компонент + запись в `KEYED_VIEWS`; для собственного
  инструмента с полноценным `presentationMeta` — смотри `dsh-osm` (карта) как эталон.
