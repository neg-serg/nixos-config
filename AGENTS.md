# AGENTS usage for this repo

Communication language (hard rule)
- The user (neg) cannot read Chinese at all. NEVER write anything to them in
  Chinese — not in chat replies, not in dsh-ui components, not in commit
  messages, not in any file they will read. Treat this as a hard rule.
- The user's language is Russian. English is acceptable for technical terms,
  code, and identifiers. When in doubt, write in Russian.
- Code comments (in .hs/.scd/.tidal/.rs/nix/… source files) are written in
  English; Russian is for chat replies, docs, and UI copy. Commit subjects
  are English imperative (see Commit style below); commit bodies may be
  Russian. (User requirement — musical code lives in the private ~/notes repo.)
- Note: the dsh web GUI itself may contain Chinese strings from plugins
  (e.g. pet.json, dshmarket UI); that is app data, not something we write.
  Do not copy those strings into replies for the user.
- Before committing, check that files you wrote contain no stray Chinese
  characters: `just lint` warns on CJK in *.md (scripts/dev/check-markdown-language.sh);
  review other text files manually.

Scope
- This AGENTS.md applies to the entire `/etc/nixos` tree.
- Prefer existing module structure (`modules/`, `hosts/`, `modules/user/nix-maid/`, etc.) and follow surrounding style.
- Nested AGENTS.md files exist for subtrees (`modules/`, `docs/`, `packages/`,
  `scripts/`, `secrets/`, `hosts/`, `files/quickshell/`). Read the nearest
  applicable one before touching that subtree; nested rules take precedence
  where they conflict with this file.

Quick Commands
- Quick switch (primary): `nh os switch /etc/nixos#odin --option substitute false`
- Build & switch (alternative): `sudo nixos-rebuild switch --flake .#odin --option substitute false`
- Build only: `nixos-rebuild build --flake .#odin --option substitute false`
- Format all: `just fmt`
- Full check: `just check` (runs `nix flake check -L --option substitute false`)
- Update flake: `just update`
- GC: `sudo nix-collect-garbage -d && nix-collect-garbage -d`

Project Structure
- `flake.nix` — entry point (NixOS + home-manager)
- `flake/` — flake helpers (`nixos.nix` with `odinDomains`, `checks.nix`, ...)
- `modules/` — system modules (features/, cli/, dev/, servers/, ...)
- `hosts/odin/` — host-specific config (services.nix, hardware.nix, networking.nix...)
- `packages/` — custom overlays and packages
- `lib/` — shared Nix helpers (opts.nix, neg-helpers.nix, package-checks.nix, ...)
- `secrets/` — SOPS-encrypted secrets
- `files/` — config files (Hyprland, Quickshell panel, scripts)
- `docs/` — manuals and howtos (`docs/manual/`, `docs/howto/`)
- `scripts/` — dev/utility scripts (`scripts/dev/*.sh`)
- `.agent/workflows/` — step-by-step change workflows (add module/package/secret/..., rebuild, theming)
- `.githooks/` — git hooks (enable with `just hooks-enable`)
- Note: `result` is a gitignored symlink to the last build; `nix/` and `viz/`
  are gitignored local/generated dirs — never commit any of them.

Feature Flags
- Most components are controlled via feature flags in `modules/features/`:
  ```nix
  features.dev.ai.omp.enable = true;
  features.cli.broot.enable = true;
  ```
- Check a flag's current value: `just flag <flag-path>`, e.g.
  `just flag features.dev.ai.omp.enable` (or `nix eval .#nixosConfigurations.odin.config.<flag-path>`).
- odin uses a restricted domain set (`odinDomains` in `flake/nixos.nix`); changes in excluded
  domains (`appimage`, `apps`) do not take effect on odin — warn the user before touching them.
  (`llm` IS active on odin.)

Nix style: `pkgs.*` lists
- When adding items like `pkgs.<name>` to `environment.systemPackages` or other package lists, add a short comment after each entry describing what the package is/does, whenever it is not completely obvious.
  - Example: `pkgs.supercollider # SuperCollider IDE and audio engine`
  - Example: `pkgs.haskellPackages.tidal # TidalCycles live-coding library`
- Keep comments concise and focused on purpose/role in the system, not marketing copy.

General guidance
- Keep changes minimal and focused on the feature you are touching.
- Avoid drive-by refactors; mention unrelated issues separately instead of fixing them silently.
- When changing behavior, prefer updating relevant docs under `docs/` or `docs/manual/` as needed.
- For WireGuard/VPN host vs user-level setup, see `docs/manual/manual.ru.md` (section “WireGuard VPN (host / user)”) for prior research and patterns.
- For a quick orientation, `docs/codebase.md` is a generated repo map (modules, features, profiles, packages); regenerate with `just codebase` when structure changes.
- For verified step-by-step change workflows (add module/flag/package/host/script/secret, docs, commit rules), see `docs/howto/agent-recipes.md`.
- Before committing: run `just fmt` then `just check`; never commit unformatted
  or failing changes.

Debugging: Iron Law (ported from hermes-agent systematic-debugging)
- NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST: reproduce the exact symptom and build a tight
  red/green loop (fast, deterministic, specific command) BEFORE reading code or proposing fixes.
- User instructions/transcript are never "fixed up" by paraphrasing into summaries; keep the source
  of intent verbatim (micro-compaction principle).
- See workflow: .agent/workflows/debugging.md.

Agent reasoning (evidence-first, ported from omp)
- Every sentence is a fact, a decision, or a risk: no ceremony, hedging, summaries, filler, or marketing.
- Assume a technical reader; don't narrate obvious steps or over-explain basics.
- Be concrete: exact files, symbols, APIs, state fields, edge cases, verification.
- When a reply involves a change or a judgment call, use this format:
  Problem — what's wrong. Decision — action & why. Check — breakage & verification. Next — concrete action.
- State uncertainty at the claim; name the tradeoff; choose the boring/safe option.
- Escalation: push back on risk-hidden plans or wrong claims — name the risk, show evidence,
  propose an alternative. If overruled, execute the user's call; don't relitigate.

Asking the user (default to action, ported from omp)
- Default to action: resolve ambiguity via repo conventions, existing patterns, and reasonable
  defaults; exhaust code, configs, docs, and history before asking.
- Ask only when options have materially different tradeoffs the user must decide; if multiple
  choices are acceptable, pick the most conservative/standard one, proceed, and state the choice.
- When asking: 2-5 concise, distinct options with short labels; tradeoffs go in the descriptions;
  batch related questions into one turn, not one at a time.
- Always ask before: touching `secrets/`, destructive/irreversible ops
  (`nix-collect-garbage`, deleting generations, removing modules/packages),
  and network/VPN/WireGuard config changes.

Web search etiquette (ported from omp)
- Prefer primary sources: papers, official docs, upstream repos; corroborate key claims with multiple
  independent sources before asserting.
- MUST link cited sources in the final answer; never present search-derived claims without references.
- NEVER use web search for content reachable directly (known GitHub repos/issues, arXiv pages, official
  docs): read the URL instead — search is for discovery, read is for content.

Secrets hygiene (ported from omp)
- NEVER print tokens, API keys, passwords, or SOPS secrets in full — mask them (e.g. `sk-***abcd`).
- If output contains a 43-char key-like placeholder, treat it as a secret and redact it.
- SOPS-encrypted secrets live in `secrets/`; never write plaintext secrets to
  the repo or into chat output. Access them via `<secret>.path` in Nix and keep
  file modes 0400/0600. Follow `secrets/AGENTS.md` before touching that subtree.

Context switching (ported from omp tan)
- When switching between projects/workspaces, state the switch explicitly and re-read the target
  project's AGENTS.md before continuing; never carry the previous project's assumptions.

Todos (ported from omp)
- Task strings are verbatim content, never auto-generated IDs ("task-1"/"task-N").
- User gives a multi-step plan, a numbered/bulleted checklist, or "N bugs/items": MUST track
  every item as its own task before working; never summarize into fewer tasks or track the
  rest from memory.
- Mark tasks done immediately after finishing; keep task strings stable.
- Never make a todo call the turn's only tool call — batch it with real work (init with first
  reads/edits; each done/start with the next action).

Goal completion audit (ported from omp)
- Before declaring a goal/task complete, audit the current repo state — never rely on
  earlier-session memory: the repo may have changed.
- Map the objective to concrete deliverables (files, behaviors, tests, gates, artifacts); then
  for each deliverable collect authoritative evidence: file contents, command output, test pass status.
- Verification scope = claim scope: a narrow check does not prove a broad claim.
- Uncertainty = not achieved: indirect evidence, partial coverage, missing artifacts, or
  uninspected "looks right" → keep working or gather stronger evidence.
- Budget exhaustion ≠ completion: never mark done merely because tokens/time are nearly out.

Golden tool set (agent habits) — hard rules
- Always prefer the fast modern replacements over legacy coreutils when working on this host.
  They are installed system-wide; the full reference (rationale, config wiring, examples,
  caveats) is `docs/howto/golden-tools.ru.md`.
  - `rg` (ripgrep) or `ugrep` instead of `grep -r`; `rg --pcre2` covers PCRE-only patterns
  - `fd` instead of `find`
  - `bat` instead of `cat` for terminal peeks (the `read` tool stays primary for files)
  - `jq` instead of `sed`/`awk` for JSON
  - `eza` instead of `ls`, `dust`/`ncdu` instead of `du`, `duf` instead of `df`, `btop`
    instead of `top`, `procs` instead of `ps`, `delta` instead of `diff` (git pager already wired)
  - `sd` for simple search-and-replace, `zoxide` for `cd`, `fzf` for interactive selection,
    `hyperfine` for benchmarking
- DSH-native tools beat shell equivalents: use the `read`/`rg`/`glob` tools (ripgrep/fd-backed)
  instead of spawning `cat`/`grep`/`find` in bash. Spawn bash only when a native tool cannot do
  the job; when a pipeline is unavoidable, still prefer rg/fd/bat/jq over grep/find/cat/sed.
- Keep legacy tools only when correctness/portability demands them: scripts meant for
  non-NixOS/remote hosts, POSIX-only contexts, or flags with no rg/fd equivalent.
  Gotcha: `rg -r` means *replace*, not recursive; recursive is the default.

Automation: desktop over CDP where applicable
- Prefer the `desktop` tool (computer-use-linux: real windows, AT-SPI semantic selectors,
  grim screenshots → local vision) for HUMAN-LIKE GUI interaction — working an application or
  a website as the user would (click/type/scroll by element name, read the actual screen).
- Use the `browser` tool (CDP, dedicated headless tabs) only for PROGRAMMATIC page access:
  DOM/text extraction, JS-driven checks, scraping structure, headless rendering — not for
  GUI-style work. When a site must be operated like a user would, desktop wins.
- Screenshots from either tool go through local VL models (qwen2.5vl) — data never leaves the host.
- Downscale captures before vision: `magick shot.png -resize 1280x small.png` — full-res 4K
  screenshots exceed the local VL context (4096 tokens). Both tools verified live end-to-end
  (screenshot → vision reading of real windows / real web page).

Builds: substitute = false
- This host is in a region where `cache.nixos.org` is unreliable (blocked/slow), so do NOT rely on binary substitution.
- Always run nix build/eval commands with `--option substitute false` (build from source), e.g.:
  `nix build .#nixosConfigurations.odin.config.system.build.toplevel --dry-run --option substitute false`
- The user's own rebuild binding uses the same flag (`nh os switch /etc/nixos#odin --option substitute false`); keep that convention in any new bindings/scripts.
- The repo's own targets already pass this flag: `just deploy*`, `just check`,
  `just docs-modules`, `just flag`. Do not introduce nix invocations without it.

Commit style
- Use a bracketed scope prefix consistent with existing history, for example: `[media/audio] …`, `[hosts/odin] …`, `[dev/pkgs] …`, `[docs] …`.
- Common scopes: nixpkgs, flake/*, core/*, hosts/<hostname>, dev/*, cli/*, hardware/*, media/*, servers/*, modules/*, packages/*, docs, ci, refactor.
- Subjects must be in imperative mood, short and specific, without a trailing period.
- Examples:
  - `[media/audio] Add TidalCycles live-coding stack`
  - `[hosts/odin] Tune cooling profile`
  - `[docs] Document audio creation stack`
