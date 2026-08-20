# Контракт авторинга скиллов SKILL.md (порт из hermes-agent)

Единый формат скиллов из **NousResearch/hermes-agent** (82 SKILL.md; контракт —
`skills/software-development/hermes-agent-skill-authoring/SKILL.md`, MIT). Цель порта: скиллы
DSH/репо получают одинаковый frontmatter и короткие описания, чтобы индекс скиллов (и напоминания
dsh-category-skill-reminder) находили их по триггеру, а не по маркетингу.

## Frontmatter

```yaml
---
name: my-skill-name               # lowercase, hyphens, <=64 символа (MAX_NAME_LENGTH)
description: Concise capability statement, <=60 символов.
version: 0.1.0                    # semver; новые скиллы стартуют с 0.1.0
author: Real Name (handle), Hermes Agent
license: MIT
platforms: [linux, macos, windows]   # аудит, не угадывать
metadata:
  hermes:
    tags: [Short, Descriptive, Tags]
    related_skills: [other-in-repo-skill]
---
```

## Правила description (HARDLINE — лимит валидатора 1024 это НЕ стандарт)

- **\<=60 символов.** Одна фраза. Заканчивается точкой.
- Capability statement, не описание реализации; не повторять имя скилла.
- Без маркетинговых слов ("powerful", "comprehensive", "seamless", "advanced").
- Индекс скиллов в system prompt обрезает на 57 символах + "..." — триггер/возможность должны
  влезать в это окно целиком.
- Если в description есть ":", обернуть в двойные кавычки (или YAML распарсит mapping и генератор
  доков упадёт). Кавычки не считаются в 60.

Хорошо: "Track named companies for material news with cited digests." Плохо: "Use when a user asks
to monitor named competitors or companies for product launches, pricing changes, funding, ..." (240
символов — отклоняется в ревью).

## Структура тела

- # Имя → ## Overview (2-4 предложения, принцип) → ## When to Use (явные триггеры) → ## Core
  method / шаги → ## When NOT to use / исключения → ## Notes (источник, лицензия, пары).
- Железные законы (если есть) — в начале, blockquote или код-блок, и дублируются в начале шагов.
- References — отдельные файлы в references/ (не раздувать SKILL.md).
- Пример-эталон в репо: skills/software-development/systematic-debugging/SKILL.md (Iron Law +
  Feedback Loop Rule + фазы + анти-паттерны).

## Discovery (4 уровня)

1. project (в рабочем проекте) → 2. opencode/user (в пользовательском каталоге) → 3. builtin
   (встроенные). Одинаковое имя на более высоком уровне перекрывает нижний.

## Skill-embedded MCP

MCP-сервер внутри скилла изолируется ключом sessionID:skill:server — состояние одного скилла не
утекает между сессиями. У DSH: скиллы из сессионного каталога; при подключении MCP — тот же принцип
изоляции.

## Порт в этот репозиторий

- Скиллы, живущие в /etc/nixos (например, будущие .agent/skills/), оформлять по этому контракту.
- Проверка: name lowercase-hyphens; description \<=60 символов; version semver; platforms реальные;
  related_skills ссылаются на существующие скиллы.
- Источник: /tmp/hermes-agent (commit 27562ad), файл
  skills/software-development/hermes-agent-skill-authoring/SKILL.md + валидатор скиллов hermes.
