# ongoing Goal — долгоиграющая цель в dsh (как развернуть)

Механика «ongoing Goal» уже развёрнута в базовом web-профиле DSH — отдельный плагин или Nix-модуль
не нужен. Здесь — как она устроена и как запустить/управлять целью.

## Что это

Одна долгоиграющая цель на сессию (same-session goal): объектив + бюджет раундов
`maxGoalRounds`, авто-продолжение раундов, пока цель активна и «взведена» (armed), и карточки/чипы
в GUI. Реализация в базовых пакетах профиля (строки в `cordis.patch.yml`):

| Строка (патч)          | Пакет                          | Роль                                                        |
| ---------------------- | ------------------------------ | ----------------------------------------------------------- |
| `goal`               | `@deepseek-ai/dsh-goal`      | сервис целей (`ctx.goals`), event-sourcing из `goal/change` |
| `goal-round-driver`  | `@deepseek-ai/dsh-goal-round-driver` | авто-продолжение раундов (agent.followup) при armed+active  |
| `command-goal`       | `@deepseek-ai/dsh-command-goal` | человеческая команда `/goal`                              |
| `ui-goal`            | `@deepseek-ai/dsh-client-ui-goal` | GoalBar в input dock (прогресс «раунды N/M»)                |
| `tool-goal`          | `@deepseek-ai/dsh-tool-goal` | model-facing инструменты (сервятся через Gateway Remote)    |

Вид цели: `{id, revision, objective, phase, activation (armed/disarmed), roundsStarted,
maxGoalRounds, blockedReason}`. Фазы: `active | paused | complete | blocked`. Проверка живого
состояния: `get_goal` из сессии отвечает `{goal: null}`, когда цели нет.

## Как запустить

1. В чате попросить агента поставить долгоиграющую цель: агент вызовет `create_goal`
   (`objective` + опционально `max_goal_rounds`). Прямо из GUI:
   `/goal <объектив>` — создать; `/goal edit <новый текст>` — изменить объектив.
2. Цель создаётся в фазе `active` со взведённой активацией (armed). Пока она armed+active,
   round-driver сам продолжает раунды в рамках той же сессии (раунд = следующий ход агента,
   `roundsStarted + 1`, бюджет не превышается).
3. Прогресс виден в GoalBar (чип «раунды N/M») и в карточке результата
   `create_goal`/`get_goal`/`update_goal` (рендер — плагин dsh-widgets).

## Управление

| Действие            | Инструмент / команда                                                              |
| ------------------- | --------------------------------------------------------------------------------- |
| Создать             | `create_goal` или `/goal <объектив>`                                          |
| Посмотреть          | `get_goal` (также `/goal` без аргументов)                                      |
| Изменить объектив   | `update_goal edit` (или `/goal edit <текст>`); `maxGoalRounds` не меняется     |
| Пауза / возобновить | `update_goal pause|resume` (или `/goal pause|resume`)                           |
| Завершить           | `update_goal complete`                                                          |
| Блокировка          | `update_goal blocked` (после минимума раундов; причина в `blockedReason`)      |
| Сбросить            | `/goal clear` (только при активной/паузной цели)                                 |

После resume/fork сессии активная цель приходит disarmed — возобновить её командой
`update_goal resume` (или просто попросить «продолжай» — агент сам перевзведёт).

## Ограничения

- Одна цель на сессию; новая поверх незавершённой — только через `/goal clear` или
  `update_goal complete`.
- `objective` и `maxGoalRounds` не меняются через edit (только объектив).
- Раунды — в рамках одной сессии; между сессиями цель не переносится (disarmed).
- Проверено на odin 2026-08-20: `get_goal` отвечает, сервис жив; плагин для этого не нужен.
