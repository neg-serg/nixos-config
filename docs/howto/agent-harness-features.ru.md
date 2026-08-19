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
- **notepad-write-guard**: защищает notepad-файлы от случайных правок агента.
- **plan-format-validator**: валидирует формат плана до исполнения.
- **task-resume-info**: при возобновлении отменённой задачи вставляет контекст задачи.
- **delegate-task-retry**: повтор неудачной делегации.
- **edit/json-error-recovery**: ловит ошибки правок/JSON и вставляет корректирующее напоминание.

### Крупные (уже частично портированы как промпты)

- **todo-continuation-enforcer** (boulder): точный текст в `agent-guards.ru.md` п.6; механика
  (countdown 2s, backoff 30s×2, max 5, пауза 5 мин) — для реализации.
- **preemptive-compaction**: упреждающая компакция до лимита токенов.
- **anthropic-context-window-limit-recovery**: восстановление после превышения окна контекста.
- **atlas**: мастер boulder/background-сессий (оркестрация продолжений).
- **unstable-agent-babysitter**: мониторинг нестабильного поведения агента между сессиями.
- **keyword-detector**: триггеры по ключевым словам сообщений (смена режима и т.п.).

## 3. Прочее

- Skill-embedded MCP: MCP-сервер внутри скилла, изоляция ключом `sessionID:skill:server` (нет утечки
  состояния между сессиями).
- Scoped permissions для скиллов (скилл приносит свои границы доступа).
- Wisdom notepads: `.omo/notepads/{plan}/learnings|decisions|issues|verification|problems.md`,
  передаются всем последующим субагентам (уже отражено в plan-before-code/delegate-task).
