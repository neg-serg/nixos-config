# Agent skills and dsh — improvement plan (2026-10-13)

Status: in progress · Owner: next agent session · Source: read-only audit of `~/.dsh/skills`,
`packages/dsh` and this repo's agent scaffolding. Written to be executed by subagents that never saw
the originating chat: every task carries its own context, verification and stop conditions.

Progress (2026-10-13): everything except T6 is written and verified — T1 and T3 (edited skills), T2
(contract rewrite committed here as `ecfbd47e`; the checker `scripts/check-skills.sh`, its
`.githooks/pre-commit` and the `j-space` frontmatter fix live in the `~/.dsh/skills` working tree)
and T4 (`wordcraft`, `dsh-worktrees`, `greeter`). The skills-repo commits are handed to the user,
because the sandbox allows the approved file edits but not git writes outside `/etc/nixos`. The
catalogue validates clean (`check-skills: OK (21 skills)`). T4's backlog, T5 (a no-op until upstream
moves) and T6 (needs the remote decision) remain.

## Why

The request was: check whether the skill library needs additions/fixes, whether dsh needs an update,
and turn the answer into a workable plan. Audit findings, all verified:

1. Skill frontmatter has three incompatible specs in the repo and one format in reality: 17 of the
   18 skills use `name`/`description`/`whenToUse`, `j-space` is missing `whenToUse`, and no skill
   carries the hermes fields the authoring doc prescribes.
1. Four skills describe the host by its old name (`odin`): `nixos`, `wine-apps`, `sops`,
   `glm-genelec` (`j-space` needed no change: its only hit is the word "re-encoding").
1. The `nixos` skill is wrong in three more places: the excluded-domain list (it claims
   `llm appimage apps`; `flake/nixos.nix:76` excludes `appimage`+`apps`, `llm` is active),
   `nix store du` (not a nix command) and `just check` quoted without `--option substitute false`.
1. `wine-apps` documents the deleted `hosts/odin/default.nix` and steps built on the removed Carla
   stack (commit `049aa437`).
1. Five skills cross-reference things that do not exist: the skill `red-green-repro`, the skill
   `untrusted-content-as-data`, `/etc/nixos/viz` plus a `visualize` tool,
   `docs/howto/golden-tools.ru.md` (and `*.ru.md` is banned), `hosts/odin/default.nix`.
1. Five skills duplicate repo docs (`nixos`, `sops`, `golden-tools`, `wine-apps`, `glm-genelec`).
1. Seven recurring areas have no skill: `wordcraft`, `dsh-worktrees`, `greeter` (128 of the last 300
   commits), `windows-vm-dockur`, `local-music-ai`, `kernel-build`, `dsh-tui-profile`.
1. The skill library is a local-only git repo: no remote, no validator, no README.
1. dsh itself is up to date: the pinned 0.2.0-rc.2 equals the npm `latest` tag (published
   2026-09-29); only 0.2.1-alpha.1/2 sit ahead on the alpha channel (2026-10-03/09).

## Ground rules for every task

- Delegation template: `.agent/workflows/delegate-task.md` (7 elements). A subagent gets TASK,
  EXPECTED OUTCOME, REQUIRED SKILLS, REQUIRED TOOLS, MUST DO, MUST NOT DO, CONTEXT.
- Skills repo (`/home/neg/.dsh/skills`): commit style `feat(<skill>): ...`; never rewrite a skill
  the workflow did not create beyond the fix the task names (autolearn rule).
- This repo (`/etc/nixos`): `just fmt` then `just check` before every commit; `[docs]` scope for
  `.agent/` and `docs/` changes; a system switch is never part of a task.
- Evidence over claims: a task is done when its VERIFY commands run green in the same session and
  the output is captured in the task report or commit message.

## T1 — Fix the stale facts in the skill library

**STATUS**: done 2026-10-13 in the `~/.dsh/skills` working tree (files: `nixos`, `wine-apps`,
`sops`, `glm-genelec`); commit pending — see Progress.

**TASK**: fix the stale host/command facts in `nixos`, `wine-apps`, `sops` and `glm-genelec` (plus
the single `odin` mention in `j-space`). **CONTEXT** (audit 2026-10-13, every line verified with a
command): rename commit `3b083548`. `nixos/SKILL.md`: `odin` x8, `#odin` switch commands, claims the
domain filter excludes `llm appimage apps` (reality: `flake/nixos.nix:76` excludes
`appimage`+`apps`; `llm` is active per `AGENTS.md:67-69`), `nix store du` fails with "du is not a
recognised command", and `just check` is quoted without `--option substitute false` (`Justfile:54`
adds it). `wine-apps/SKILL.md`: `odin` x8, `hosts/odin/default.nix` no longer exists (now
`hosts/trantor/default.nix:162-165`), and the `carlactl` steps reference the removed Carla stack
(`049aa437`, `docs/howto/wine-vst-bridge.md:29`). `sops/SKILL.md`: `#odin` switch step, and the
switch is written as an agent action while `AGENTS.md:207-212` hands it to the user.
`glm-genelec/SKILL.md`: odin in the title, and `hdspe-init-mixer` treated as a command — only the
systemd unit `hdspe-init-mixer.service` exists. **STEPS**: read every hit in context; replace the
host name; fix the domain list, the two nix commands and the flag quote; drop or rewrite the
carlactl steps; make the sops switch a hand-over; leave dated/historical notes untouched.
**VERIFY**: `rg -n 'odin|#odin' ~/.dsh/skills/` returns only genuine history;
`rg -n carlactl ~/.dsh/skills/` empty; `systemctl status hdspe-init-mixer` active and the skill no
longer calls it a command; `just flag features.llm.enable` in `/etc/nixos` prints `true`. **DONE**:
one commit in the skills repo naming the five files. **MUST NOT**: touch any other prose, reword
descriptions, or move files.

## T2 — One skill frontmatter contract + a validator

**STATUS**: done 2026-10-13 — the contract rewrite is committed here (`ecfbd47e`); the checker, the
hook and the `j-space` fix are staged in the skills repo (commit pending). The checker reports
`OK (21 skills)` on the catalogue and fails a fixture whose directory name breaks the contract.

**TASK**: make the repo's skill docs describe the format dsh actually loads, and add a checker.
**CONTEXT**: three specs today — `docs/howto/agent-skill-authoring.md` (hermes: English, description
\<=60 chars, version/author/license/platforms/metadata.hermes), `.agent/workflows/autolearn.md`
(`name`/`description` \<=200 chars/`whenToUse`), and reality: 17 of the 18 skills carry `name` +
Russian `description` + `whenToUse` (`j-space` is missing `whenToUse`), no skill carries any hermes
field, and the reminder plugin reads exactly `name`/`description`
(`modules/user/nix-maid/apps/dsh-category-skill-reminder/lib/index.js:126`). **DECISION** (do not
relitigate): the dsh-native format is the contract; the hermes fields stay as an optional annex for
skills that want them. **STEPS**: rewrite the relevant sections of both docs; add
`~/.dsh/skills/scripts/check-skills.sh` validating: frontmatter fences, `name` equals the directory
and is kebab-case, `description` and `whenToUse` present and non-empty, every `scripts/...` path
mentioned in a body exists, optional hermes fields well-formed when present; fix the one known
failure (`j-space` has no `whenToUse`); wire the checker as a pre-commit hook in the skills repo and
mention it in the README (T6). **VERIFY**: run the checker over the library after the `j-space` fix
(expect 0 failures); copy a skill to a fixture dir with a broken `name` (expect one failure naming
that file). **DONE**: docs updated here (`[docs]` commit) + checker and hook committed in the skills
repo.

## T3 — Repair the dangling cross-references

**STATUS**: done 2026-10-13 in the working tree (`fault-localization-first`, `memory-trust-hygiene`,
`golden-tools`, `interactive-cards` — the last one shrank to the surviving `ask_user_question`
surface, since `visualize` went away with the web GUI); commit pending.

**TASK**: make every skill reference point at something that exists. **CONTEXT** (verified
2026-10-13): `fault-localization-first:22` names the skill `red-green-repro`, which was never added;
`memory-trust-hygiene:20` names `untrusted-content-as-data` (the intended target is the existing
`agent-security-hygiene`); `interactive-cards:11,17,20,53` references `/etc/nixos/viz` (absent) and
a `visualize` skill/tool (absent from the harness); `golden-tools:10` cites
`docs/howto/golden-tools.ru.md`, which does not exist and would be banned by the English-only docs
rule. **DECISION**: point `fault-localization-first` at `verify-by-execution` (it already owns the
red/green loop) instead of minting a new skill; repoint `memory-trust-hygiene` at
`agent-security-hygiene`; rework the `interactive-cards` references to what the harness actually
offers; link `golden-tools` to `docs/howto/golden-tools.md`. **STEPS**: one line per reference; no
body rewrites. **VERIFY**:
`rg -n 'red-green-repro|untrusted-content-as-data|golden-tools\.ru\.md|/etc/nixos/viz' ~/.dsh/skills/`
empty; every skill name mentioned in a body exists as a directory. **DONE**: skills repo commit.
**MUST NOT**: delete skills or repurpose them.

## T4 — Add the missing skills (independent commits, in this order)

**STATUS**: `wordcraft`, `dsh-worktrees` and `greeter` written 2026-10-13 (commits pending); the
backlog (`windows-vm-dockur`, `local-music-ai`, `kernel-build`, `dsh-tui-profile`) remains open.

**TASK**: create the skills below; each is its own commit and can be delegated on its own. **CONTEXT
— wordcraft** (all verified 2026-10-13): package `packages/wordcraft/default.nix` (source build of
tag v0.6.1, `doCheck = false`, runtime wrapper for wgpu/winit dlopens); module
`modules/text/wordcraft.nix` behind `features.text.wordcraft`; fonts: the app scans
`/usr/share/fonts` + `~/.local/share/fonts` itself and **ignores fontconfig**, the module links
`carlito`/`caladea`/`liberation`/`dejavu`/`noto-cjk-sans`/`noto-emoji`; MIME defaults in
`modules/user/nix-maid/gui/xdg.nix`; CLI: `wordcraft-cli convert|text|inspect|render|run|mcp`;
upstream limits: proofing only en/pl/pt (upstream issue #8), the UI language follows the locale;
documentation: `docs/howto/wordcraft.md`. **CONTEXT — dsh-worktrees**: `docs/howto/dsh-worktrees.md`
exists and `subagent-context-offload` tells writers to use worktrees, but no skill covers the
procedure. **CONTEXT — greeter**: 128 of the last 300 commits are `[greeter]`; only
`docs/howto/nixie-tube.md` documents a slice; needs a survey (commits, `files/quickshell/greeter`)
before drafting. **BACKLOG** (add only after the three above): `windows-vm-dockur` (only the
no-sound slice lives in `glm-genelec`), `local-music-ai` (`docs/howto/local-music-ai.md`,
`just fix-music-venvs`), `kernel-build` (`docs/runbook-kernel-autofdo.md`), `dsh-tui-profile`
(`docs/howto/dsh-tui-profile.md` — facts that break a boot). **STEPS**: draft per the autolearn
criteria and the T2 contract; one screen per skill; for `wordcraft` include `convert`, `inspect` and
the font check (`strings out.pdf | grep -oE '/BaseFont/[A-Z]+\+[A-Za-z0-9-]+' | sort -u`) plus a
pointer to the version-bump procedure. **VERIFY**: checker green; the skill appears in a dsh
session's catalog for `/etc/nixos` (or is present with valid frontmatter); every claim matches the
file it cites. **DONE**: one skills repo commit per skill, `feat(<skill>): ...`. **MUST NOT**: batch
several skills into one commit; invent commands the cited files do not contain.

## T5 — dsh update (verdict: nothing to do today)

**VERDICT (2026-10-13): no update needed.** `packages/dsh/default.nix` pins `0.2.0-rc.2`, the npm
registry's `latest` tag is the same version (published 2026-09-29), and the installed
`dsh --version` reports `0.2.0-rc.2`. The only newer code is the alpha channel (`0.2.1-alpha.1`
2026-10-03, `0.2.1-alpha.2` 2026-10-09) — pre-releases that would mean rebasing the package's source
patches (`patch-session-format.py`, `patch-widgets.py`, and the `grep`→`rg` sed anchors in
`post-install.sh`, all keyed to 0.2.0-rc.2 file contents) for no user-visible need. The full audit
(2026-10-13, subagent) adds: the alpha carries new plugins/tools (git-worktrees, working_directory,
Claude Code bundles) plus breaking chores (invariant plugins removed, mixed tool-presentation
dropped, per-row dshHome removed) and the loader dep `node-addon-require-builtin` `^0.1.6` →
`^0.1.9` — the native loader that forced `nodejs-official.nix`, so re-verify the runtime on any
bump. **WHEN TO UPDATE** (watch dist-tag `latest` and GH releases for `0.2.1-rc.1` or a `0.2.0`
final): bump `version`, tarball hash and `npmDepsHash` in `packages/dsh/default.nix`; regenerate
`package-lock.json` from the new tarball with devDependencies stripped (same `runCommand` recipe);
then rebase the patchers against the exact target tarball — `patch-widgets.py` fails its count
assertions (the `subagent` anchor matches 0× on 0.2.1-alpha.2, and `dsh-tool-ralph`/`dsh-webhook`
are no longer direct deps, so drop or guard those patches), `patch-session-format.py` anchors still
match, and `post-install.sh`'s `call.name === "grep"` anchor now occurs twice (`sed -g` covers it —
review the second site). Finally `just fmt`/`just check`, rebuild the closure and smoke
`dsh --version` plus one session boot. **WATCH**: the wrapper execs the store binary, so dsh cannot
self-update here; an update is always a repo commit — do not add an updater.

## T6 — Governance of the skill library

**TASK**: give the skills repo a README and a backup path. **CONTEXT**: `/home/neg/.dsh/skills` is
local-only (`git remote -v` empty), 18 skills, gitignore for Python artifacts. The language policy
of `/etc/nixos` is English-only for `*.md`, while the skills are Russian — the library stays OUT of
`/etc/nixos` unless it is translated or the checker gets an explicit exception. **STEPS**: write
`README.md` (contract pointer, how autolearn adds skills, how to run the checker); agree on a
remote/mirror with the user; enable the pre-commit hook from T2. **VERIFY**:
`git -C ~/.dsh/skills remote -v` shows the agreed remote; `git -C ~/.dsh/skills status` clean after
the hook runs. **MUST NOT**: push anywhere before the user approves the destination.

## Open questions for the user

- Remote destination for the skills repo (private GitHub? Codeberg?) — needed by T6.
- Consolidation: shrink the five doc-duplicating skills into trigger + pointer stubs (rule: durable
  prose lives in `docs/`, a skill carries the trigger and the gotchas), or keep them as they are?
  The audit recommends shrinking; this is a user call.
- `rutracker` drives Vivaldi over raw CDP while `AGENTS.md` says CDP is not used: the rule bans the
  browser tool, not this workaround, but decide before anyone edits that skill.
- Should project skills (`nixos`, `wine-apps`, `wordcraft`) move to `/etc/nixos/.dsh/skills`?
  Blocked today by the English-only markdown policy in this repo.
