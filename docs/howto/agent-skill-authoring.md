# SKILL.md skill-authoring contract (port from hermes-agent)

Unified skill format from **NousResearch/hermes-agent** (82 SKILL.md; the contract —
`skills/software-development/hermes-agent-skill-authoring/SKILL.md`, MIT). Port goal: DSH/repo
skills get identical frontmatter and short descriptions, so the skill index (and
dsh-category-skill-reminder reminders) find them by trigger, not by marketing.

## Frontmatter

```yaml
---
name: my-skill-name               # lowercase, hyphens, <=64 characters (MAX_NAME_LENGTH)
description: Concise capability statement, <=60 characters.
version: 0.1.0                    # semver; new skills start at 0.1.0
author: Real Name (handle), Hermes Agent
license: MIT
platforms: [linux, macos, windows]   # audit, don't guess
metadata:
  hermes:
    tags: [Short, Descriptive, Tags]
    related_skills: [other-in-repo-skill]
---
```

## description rules (HARDLINE — the validator's limit of 1024 is NOT the standard)

- **\<=60 characters.** One sentence. Ends with a period.
- Capability statement, not an implementation description; don't repeat the skill name.
- No marketing words ("powerful", "comprehensive", "seamless", "advanced").
- The skill index in the system prompt truncates at 57 characters + "..." — the trigger/capability
  must fit entirely in that window.
- If description contains ":", wrap it in double quotes (otherwise YAML parses a mapping and the
  docs generator crashes). Quotes don't count toward the 60.

Good: "Track named companies for material news with cited digests." Bad: "Use when a user asks to
monitor named competitors or companies for product launches, pricing changes, funding, ..." (240
characters — rejected in review).

## Body structure

- # Name → ## Overview (2-4 sentences, the principle) → ## When to Use (explicit triggers) → ## Core
  method / steps → ## When NOT to use / exceptions → ## Notes (source, license, pairs).
- Iron laws (if any) go at the beginning, in a blockquote or code block, and are duplicated at the
  start of the steps.
- References — separate files in references/ (don't bloat SKILL.md).
- Reference example in the repo: skills/software-development/systematic-debugging/SKILL.md (Iron Law
  \+ Feedback Loop Rule + phases + anti-patterns).

## Discovery (4 levels)

1. project (in the working project) → 2. opencode/user (in the user directory) → 3. builtin
   (built-in). A skill with the same name at a higher level overrides the lower one.

## Skill-embedded MCP

An MCP server inside a skill is isolated by the sessionID:skill:server key — the state of one skill
doesn't leak between sessions. For DSH: skills come from the session directory; when MCP is
connected, the same isolation principle applies.

## Port into this repository

- Skills living in /etc/nixos (e.g., future .agent/skills/) must follow this contract.
- Checks: name lowercase-hyphens; description \<=60 characters; version semver; platforms real;
  related_skills reference existing skills.
- Source: /tmp/hermes-agent (commit 27562ad), the file
  skills/software-development/hermes-agent-skill-authoring/SKILL.md + the hermes skill validator.
