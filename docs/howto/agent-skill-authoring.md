# SKILL.md authoring contract (the skill catalogue and this repo)

The contract for the skills in `~/.dsh/skills` (the deployed catalogue) and for any future
repo-hosted skills. It describes the format dsh actually loads: the session index and the
`dsh-category-skill-reminder` plugin read `name`/`description`
(`modules/user/nix-maid/apps/dsh-category-skill-reminder/lib/index.js`), and every deployed skill
follows the shape below.

## Frontmatter (required)

```yaml
---
name: my-skill-name # kebab-case, must equal the directory name
description: "<one sentence; the session index shows only its first ~55 characters>"
whenToUse: "<when the skill must load, in the user's own phrasing>"
---
```

- `name` — lowercase, hyphen-separated; the directory name must match.
- `description` — one sentence in the catalogue's language (the deployed skills are Russian because
  the user is; repo docs stay English). Lead with the trigger: the system-prompt index truncates
  around 57 characters + "...", so filler at the start hides the skill.
- `whenToUse` — the load condition as the user would phrase it ("user asks X, Y, Z"), not a
  restatement of the description.
- Quote any value containing `:` or YAML parses it as a mapping.

## Frontmatter (optional annex for hermes-hosted skills)

Skills ported from a hermes-agent catalogue may carry their provenance fields; they are validated
only when present:

```yaml
version: 0.1.0 # semver
author: Name (handle)
license: MIT
platforms: [linux, macos] # audit, don't guess
metadata:
  hermes:
    tags: [Short, Descriptive, Tags]
    related_skills: [other-skill] # must exist in the catalogue
```

Before 2026-10-13 this annex was the whole contract, which contradicted both the autolearn template
and every deployed skill.

## Body structure

- `# Name` → overview (2–4 sentences: the principle) → steps/commands → gotchas → notes.
- Iron laws at the top, in a blockquote or fenced block, repeated at the start of the steps.
- One screenful. Depth goes to `references/` or `scripts/` next to SKILL.md; long recipes belong in
  `/etc/nixos/docs/` while the skill keeps the trigger and the gotchas.
- A skill named in the body must exist in the catalogue, and a `docs/...` path must exist in
  `/etc/nixos` — `scripts/check-skills.sh` checks both.

## Discovery

1. project (`<projectRoot>/.dsh/skills`) → 2. user (`~/.dsh/skills`) → 3. built-in. A skill with the
   same name at a higher level overrides the lower one. An MCP server inside a skill is isolated by
   the `sessionID:skill:server` key.

## Checks

- `bash ~/.dsh/skills/scripts/check-skills.sh` — hard checks: frontmatter (name equals the
  directory, kebab-case, non-empty `description` and `whenToUse`), `scripts/...` paths that exist,
  `docs/...` paths that exist in `/etc/nixos`, `related_skills` entries that exist. Advisory lines
  flag hyphenated backticked citations that match no directory; they are noisy by nature (a tool
  name looks like a skill name), so review them rather than obeying them.
- The skills repo wires the checker as a pre-commit hook: `.githooks/pre-commit` plus
  `git config core.hooksPath .githooks`; the hook skips itself when the script is absent.
- Historical origin of the annex: the hermes-agent skill validator (`/tmp/hermes-agent`, commit
  27562ad) — the deployed contract above supersedes it.
