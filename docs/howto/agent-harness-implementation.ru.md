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

| Файл                         | Что внутри                                                                                                                                                                                                                                                                                             | Статус   |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------- |
| `designs/dsh-recon.md`       | карта интеграции: пакеты, плагины, события, точки встройки для всех 5 фич                                                                                                                                                                                                                              | ✅ готов |
| `designs/rules-hooks.md`     | 4 маленьких хука: agent-usage-reminder (S), compaction-todo-preserver (S), rules-injector (M), category-skill-reminder (S–M); все — server plugin в пресете neg; порядок: usage → todo-preserver → rules → category                                                                                    | ✅ готов |
| `designs/hashline.md`        | hash-якорные правки: `read_hashline` + `hashline_edit`, xxHash32 → CID (ZPMQVRWSNKTXJBYH), CAS `fs/write-intent`, MVP 1.5–3 дня клиентским форк-плагином; теги встроенного `read` — фаза 2 (патч `dsh-tool-fs`)                                                                                        | ✅ готов |
| `designs/memory-pipeline.md` | два готовых промпта (memory-extract, memory-consolidate) + интеграция с memento: триггеры, маппинг в треки/скиллы, бюджеты, approval-gate                                                                                                                                                              | ✅ готов |
| `designs/boulder.md`         | boulder: поведенческая спецификация (countdown 2s, backoff 30s×2 max 5, пауза 5 мин, stagnation max 3, compaction guard 60s, полный список «когда НЕ вставлять»), интеграция (`packages/dsh-boulder/` в форке), skeleton: package.json + constants (точный текст) + index.ts (хост-логика) + client.ts | ✅ готов |

## Рекомендованный порядок внедрения (серверные плагины, пресет neg)

1. **agent-usage-reminder** (S) — `agent/pre-step`, напоминание про специализированных агентов.
1. **compaction-todo-preserver** (S) — `compaction/end` → пере-инжект live todo-списка
   (`systemPrompt.section`/context — самый дешёвый вариант).
1. **rules-injector** (M) — `tools/post-execute` на `read`: подъём `rules/*.md` от каталога файла
   (как AGENTS.md discovery) + `additionalContexts`.
1. **category-skill-reminder** (S–M) — напоминание скиллов под категорию делегирования (v0 можно
   docs-only).
1. **memory-extract/consolidate** — промпты готовы; интеграция: хук `session/disposed` /
   `compaction/end` в `dsh-memento` (или плагин с `inject: ['memory','sessions']`), запись через
   `ctx.memory.add` с approval-gate, SKILL.md в `<root>/.dsh/skills/<name>/`.
1. **boulder** — по дизайну (ожидается); хук `agent/status` idle + `todo/write`-скан +
   `agent.followup` с точным текстом CONTINUATION_PROMPT из `agent-guards.ru.md`.
1. **hashline** — MVP клиентским форк-плагином; затем патч `dsh-tool-fs` для тегов встроенного read.

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
