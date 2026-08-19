# Фичи харнесса: дизайны и план внедрения (сборка из субагентов)

Сводка по результатам параллельной работы: карта интеграции DSH (recon) + дизайны четырёх групп фич,
сделанные субагентами. Полные тексты — в `docs/howto/designs/`.

## Ключевой вывод разведки

DSH web — это Cordis-хост, собранный патч-файлами; серверные плагины = форк-пакеты с
`cordis.patch.yml` (ряд в профиле), клиентские плагины = только UI браузера, `patch.py` = строковые
правки скомпилированных бандлов (для логики не использовать). Нужные хуки уже есть: `agent/status`
(idle), `turn/end`, `tools/post-execute` (результаты), `tools/execute` (обёртка аргументов),
`compaction/*`, `todo/write`, `goal/change`. Образец авто-продолжения — `dsh-goal-round-driver`
(`agent.followup`). Todo = последнее `todo/write`-событие (last-write-wins). Memento — сторонний
плагин `dsh-memento` (`ctx.provide('memory')`, SQLite `~/.dsh/dsh-memento/`).

## Дизайны

| Файл                                                                       | Что внутри                                                                                                                                                                                                                                                                                             | Статус    |
| -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------- |
| `designs/dsh-recon.md`                                                     | карта интеграции: пакеты, плагины, события, точки встройки для всех 5 фич                                                                                                                                                                                                                              | ✅ готов  |
| `designs/rules-hooks.md`                                                   | 4 маленьких хука: agent-usage-reminder (S), compaction-todo-preserver (S), rules-injector (M), category-skill-reminder (S–M); все — server plugin в пресете neg; порядок: usage → todo-preserver → rules → category                                                                                    | ✅ готов  |
| `designs/hashline.md`                                                      | hash-якорные правки: `read_hashline` + `hashline_edit`, xxHash32 → CID (ZPMQVRWSNKTXJBYH), CAS `fs/write-intent`, MVP 1.5–3 дня клиентским форк-плагином; теги встроенного `read` — фаза 2 (патч `dsh-tool-fs`)                                                                                        | ✅ готов  |
| `designs/memory-pipeline.md`                                               | два готовых промпта (memory-extract, memory-consolidate) + интеграция с memento: триггеры, маппинг в треки/скиллы, бюджеты, approval-gate                                                                                                                                                              | ✅ готов  |
| `.agent/prompts/memory-extract.md`, `.agent/prompts/memory-consolidate.md` | готовые промпты (RU), извлечены из дизайна                                                                                                                                                                                                                                                             | ✅ в репо |
| `designs/boulder.md`                                                       | boulder: поведенческая спецификация (countdown 2s, backoff 30s×2 max 5, пауза 5 мин, stagnation max 3, compaction guard 60s, полный список «когда НЕ вставлять»), интеграция (`packages/dsh-boulder/` в форке), skeleton: package.json + constants (точный текст) + index.ts (хост-логика) + client.ts | ✅ готов  |

## Статус внедрения (обновлено)

Все 7 пунктов плана **реализованы** и закоммичены как серверные плагины в
`modules/user/nix-maid/apps/` (паттерн dsh-osm: package.json + lib/index.js + ensure + patch-row):

1. ✅ **dsh-agent-usage-reminder** — `tools/post-execute` + `additionalContexts`.
1. ✅ **dsh-compaction-todo-preserver** — `session/event` compaction/start→end, пере-аппенд
   `todo/write`.
1. ✅ **dsh-rules-injector** — `tools/post-execute` на read: `rules/*.md` + корневой AGENTS.md
   (frontmatter alwaysApply/glob, дедуп на сессию).
1. ✅ **dsh-category-skill-reminder** — агент-плоскость (`dsh-liangshen-fork/agent.cordis.yml`),
   каталог скиллов через `ctx.skills.snapshot`.
1. ✅ **dsh-memory-extractor** — `session/end-seed`/`compaction/end` → draft-extract в memento;
   **TODO**: LLM-шаг (нет сервиса вызова модели у плагинов в этой сборке DSH).
1. ✅ **dsh-boulder** — `agent/status` idle + todo-проекция + `agent.steer` с CONTINUATION_PROMPT
   (countdown 2s, backoff 5s×2, max 5, пауза 5 мин, stagnation 3, compaction guard 60s) +
   toast-client.
1. ✅ **dsh-hashline** — `read_hashline` + `hashline_edit` (FNV-1a → CID, валидация хэшей, атомарная
   запись); протестирован функционально.

Плюс: **dsh-debug** — DAP-отладка (gdb/lldb-dap/dlv/debugpy/js-debug-adapter, launch/attach,
breakpoints/stepping/inspection/evaluate; протестирован на gdb). Ограничение: gdb 17.2 DAP отдаёт
пустые `threads` после attach.

Осталось: `vscode-js-debug` в systemPackages (вступит в силу после `nixos-rebuild switch`); hashline
phase 2 (теги во встроенном `read` — патч `dsh-tool-fs`).

## Что уже в репо из этого порта

- `.agent/workflows/notepads.md` — notepad-система
  (learnings/decisions/issues/verification/problems), читать перед делегированием, аппендить после
  задачи, передавать всем последующим субагентам.
- `agent-guards.ru.md` §6 — точный текст boulder-инъекции (CONTINUATION_PROMPT) + механика backoff.
- `agent-memory-pipeline.ru.md` — концепция двухстадийной памяти (дизайн субагента — детализация).

## Открытые вопросы

- Где живут форк-плагины neg-пресета (путь профиля `~/.dsh/profiles/web/` vs
  `modules/user/nix-maid/apps/`) — recon указывает на серверные плагины, но каталог исходников форка
  для новых пакетов надо выбрать (например `packages/dsh/server-plugins/`).
- `dsh-memento` правится как сторонний плагин в профиле или через форк — уточнить при внедрении п.5.
- boulder: точный сценарий «не вставлять при ожидании ответа пользователя» требует проверки
  `agent/inbox`/pending-question, как в omo.
