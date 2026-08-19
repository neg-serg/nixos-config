______________________________________________________________________

## description: Autolearn — promote repeated successful techniques into SKILL.md playbooks (ported from omp learn/manage_skill)
______________________________________________________________________

# Autolearn

After solving an insight that is likely to pay off again, promote it into a reusable skill.
Not every fact — only repeatable procedures worth codifying.

## Criteria (all must hold)

1. **Repeatable procedure** — a workflow with steps (setup sequence, debugging recipe, project
   workflow), not a one-off fact or decision.
1. **Solved a real problem** — it unblocked work or fixed something; not a hypothetical preference.
1. **Likely to recur** — you expect to need it again within weeks.
1. **Not already covered** — check the existing skill catalog (memory query / skill list) first;
   prefer enhancing an existing skill over creating a near-duplicate.

## Steps

1. **Draft the SKILL.md** with YAML frontmatter:

   ```markdown
   ---
   name: <kebab-case-name>
   description: <one sentence, <= 200 chars>
   whenToUse: <one sentence: when to load this skill>
   ---

   <concrete steps, commands, gotchas — what worked>
   ```

1. **Write it** to `<projectRoot>/.dsh/skills/<name>/SKILL.md` (workspace-scoped) or
   `~/.dsh/skills/<name>/SKILL.md` (cross-workspace). Only SKILL.md is auto-loaded; optional
   scripts/templates/examples live in the same directory.

1. **Never touch user-authored skills** — only create new ones or update skills this workflow
   created.

1. **Keep it small** — one screenful max; trim to the reusable essence.

## Notes

- A durable FACT (not a procedure) goes to memory instead: `memory add` (see memory-extract
  pipeline) — do not mint a skill for it.
- If the catalog grows past ~20 skills, consolidate: merge related skills, archive unused ones.
- This is the DSH-native version of omp's learn/manage_skill: no plugin needed, just discipline.
