# AGENTS usage for docs/

Scope

- Applies to all files under `docs/`.
- Repo-wide rules from the root AGENTS still apply.

Guidelines

- Documentation is English-only (hard rule). Never create or edit
  `*.ru.md` / `*.ru.mdown` / `*.ru.markdown` files and never write doc
  prose in Russian — there are no Russian docs in this repo and none may
  reappear. Chat replies and UI copy stay Russian; that does not apply to
  docs.
- Each topic exists as a single English source of truth. Do not create
  language twins; update the existing file when behavior or workflows
  change.
- Cross-link new documents from `docs/index.md` where relevant; prefer
  concise, task-focused notes.
- Reuse existing scripts or commands referenced in docs instead of
  inventing new ones unless needed.
- If you find Cyrillic or CJK in any `docs/**/*.md`, translate the prose
  to English (code/commands stay verbatim) — do not leave it for later.
