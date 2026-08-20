# Фичи харнесса: бэклог (из omp / oh-my-opencode)

Это не промпты, а фичи харнесса — кандидаты на реализацию в DSH/врапперах. Зафиксированы как бэклог
с источниками.

## 1. Hashline: правки по хэшам строк (oh-my-opencode)

Проблема: «harness problem» — большинство ошибок агента не в модели, а в edit-инструменте. Решение:
каждая прочитанная строка получает тег `{line}#{hash}` (CID-алфавит `ZPMQVRWSNKTXJBYH`, 2 символа),
правки ссылаются на теги, при расхождении хэша правка отклоняется до коррупции.

- Операции: replace / append / prepend; autocorrect при сдвиге строк.
- Ошибки: hash mismatch, invalid reference, overlapping ranges.
- Заявленный эффект (README): успех правок Grok Code Fast 6.7% → 68.3%.
- В omp аналогия: `[FILENAME#TAG]`-снапшоты в read.

Статус: фича харнесса, отдельный ресёрч/задача.

## 2. Хуки-кандидаты (oh-my-opencode, 46 шт. в 3 тира)

### Маленькие, сразу полезные

- **category-skill-reminder**: напоминает загрузить скиллы под выбранную категорию делегирования.
- **agent-usage-reminder**: напоминает использовать специализированных агентов/инструменты.
- **compaction-todo-preserver**: сохраняет todo-список через компакцию сессии.
- **rules-injector**: инжектит правила (`rules/*.md` с glob-условиями и alwaysApply) при чтении.

### Оценка реализуемости (2026-08-20, факты из репо/стора)

| Хук                                     | Seam в DSH                                                                                 | Сложность | Рекомендация                                                                   |
| --------------------------------------- | ------------------------------------------------------------------------------------------ | --------- | ------------------------------------------------------------------------------ |
| notepad-write-guard                     | `tools/pre-execute` deny на write/edit по .agent/notepads/\*\*                          | малая     | ✅ **реализован** (dsh-notepad-write-guard, 6/6 тестов)                        |
| plan-format-validator                   | `tools/post-execute` на write плана + agent/pre-step ре-инжект                             | средняя   | 🟡 делать после notepad-guard (частично покрыт plan-before-code.md как промпт) |
| task-resume-info                        | agent/pre-step + `session/event` (нет сигнала resume — нужен ресёрч)                       | средняя   | 🟡 отложить (нет явного resume-события)                                        |
| delegate-task-retry                     | tools/post-execute на subagent при ошибке → steer                                          | средняя   | 🟡 отложить (subagent-ошибки редки; паттерн в delegate-task.md)                |
| edit/json-error-recovery                | agent/pre-step + last tool error → steer с подсказкой                                       | малая     | ✅ **реализован** (dsh-json-error-recovery, 7/7 тестов)                        |
| preemptive-compaction                   | `compaction/start` / context-meter (JObwrW_trigger data-pct) + ctx.compaction              | высокая   | 🟡 отложить (уже есть штатный лимит; риск двойной компакции)                   |
| anthropic-context-window-limit-recovery | agent/request-error (код переполнения) → steer                                             | средняя   | 🟡 отложить (редко на local-моделях)                                           |
| atlas (мастер фоновых сессий)           | воркфлоу notepads.md + plan-before-code.md уже покрывают                                   | —         | ✅ покрыто воркфлоу (не плагин)                                                |
| unstable-agent-babysitter               | agent/status (idle-циклы) + boulder-механика                                               | средняя   | 🟡 отложить (пересекается с boulder)                                           |
| keyword-detector                        | agent/pre-step + last user text regex → hint                                                | малая     | ✅ **реализован** (dsh-keyword-detector, 7/7 тестов)                           |

Итог: **реализованы** — notepad-write-guard, edit/json-error-recovery, keyword-detector (все малые,
один рецепт: pre-step + инжект). **Покрыто воркфлоу** — atlas. **Отложить** — остальные (нет seam /
пересекаются / риск двойной компакции).

### Крупные (уже частично портированы как промпты)

- **todo-continuation-enforcer** (boulder): точный текст в `agent-guards.ru.md` п.6; механика
  (countdown 2s, backoff 30s×2, max 5, пауза 5 мин) — ✅ реализован плагином dsh-boulder.
- **preemptive-compaction**: упреждающая компакция до лимита токенов — 🟡 отложено (см. таблицу).
- **anthropic-context-window-limit-recovery**: восстановление после превышения окна контекста — 🟡
  отложено.
- **atlas**: мастер boulder/background-сессий (оркестрация продолжений) — ✅ покрыто воркфлоу
  notepads.md.
- **unstable-agent-babysitter**: мониторинг нестабильного поведения агента между сессиями — 🟡
  отложено.
- **keyword-detector**: триггеры по ключевым словам сообщений (смена режима и т.п.) — ✅ к
  реализации.

## 3. Прочее

- Skill-embedded MCP: MCP-сервер внутри скилла, изоляция ключом `sessionID:skill:server` (нет утечки
  состояния между сессиями).
- Scoped permissions для скиллов (скилл приносит свои границы доступа).
- Wisdom notepads: `.omo/notepads/{plan}/learnings|decisions|issues|verification|problems.md`,
  передаются всем последующим субагентам (уже отражено в plan-before-code/delegate-task).
