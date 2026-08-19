# AGENTS usage for this repo

Communication language (hard rule)
- The user (neg) cannot read Chinese at all. NEVER write anything to them in
  Chinese — not in chat replies, not in dsh-ui components, not in commit
  messages, not in any file they will read. Treat this as a hard rule.
- The user's language is Russian. English is acceptable for technical terms,
  code, and identifiers. When in doubt, write in Russian.
- Code comments (in .hs/.scd/.tidal/.rs/nix/… source files) are written in
  English; Russian is for chat replies, commit messages, docs, and UI copy.
  (User requirement — musical code lives in the private ~/notes repo.)
- Note: the dsh web GUI itself may contain Chinese strings from plugins
  (e.g. pet.json, dshmarket UI); that is app data, not something we write.
  Do not copy those strings into replies for the user.

Scope
- This AGENTS.md applies to the entire `/etc/nixos` tree.
- Prefer existing module structure (`modules/`, `hosts/`, `modules/user/nix-maid/`, etc.) and follow surrounding style.

Quick Commands
- Build & switch: `sudo nixos-rebuild switch --flake .#odin --option substitute false`
- Quick switch: `nh os switch /etc/nixos#odin --option substitute false`
- Build only: `nixos-rebuild build --flake .#odin --option substitute false`
- Format all: `just fmt`
- Full check: `just check` (runs `nix flake check -L`)
- Update flake: `just update`
- GC: `sudo nix-collect-garbage -d && nix-collect-garbage -d`

Project Structure
- `flake.nix` — entry point (NixOS + home-manager)
- `modules/` — system modules (features/, cli/, dev/, servers/, ...)
- `hosts/odin/` — host-specific config (services.nix, hardware.nix, networking.nix...)
- `packages/` — custom overlays and packages
- `secrets/` — SOPS-encrypted secrets
- `files/` — config files (Hyprland, Quickshell panel, scripts)
- `.agent/workflows/` — step-by-step change workflows (add module/package/secret/..., rebuild, theming)

Feature Flags
- Most components are controlled via feature flags in `modules/features/`:
  ```nix
  features.dev.ai.omp.enable = true;
  features.cli.broot.enable = true;
  ```
- odin uses a restricted domain set (`odinDomains` in `flake/nixos.nix`); changes in excluded
  domains (`llm`, `appimage`, `apps`) do not take effect on odin — warn the user before touching them.

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

Web search etiquette (ported from omp)
- Prefer primary sources: papers, official docs, upstream repos; corroborate key claims with multiple
  independent sources before asserting.
- MUST link cited sources in the final answer; never present search-derived claims without references.
- NEVER use web search for content reachable directly (known GitHub repos/issues, arXiv pages, official
  docs): read the URL instead — search is for discovery, read is for content.

Secrets hygiene (ported from omp)
- NEVER print tokens, API keys, passwords, or SOPS secrets in full — mask them (e.g. `sk-***abcd`).
- If output contains a 43-char key-like placeholder, treat it as a secret and redact it.

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

Builds: substitute = false
- This host is in a region where `cache.nixos.org` is unreliable (blocked/slow), so do NOT rely on binary substitution.
- Always run nix build/eval commands with `--option substitute false` (build from source), e.g.:
  `nix build .#nixosConfigurations.odin.config.system.build.toplevel --dry-run --option substitute false`
- The user's own rebuild binding uses the same flag (`nh os switch /etc/nixos#odin --option substitute false`); keep that convention in any new bindings/scripts.

Commit style
- Use a bracketed scope prefix consistent with existing history, for example: `[media/audio] …`, `[hosts/odin] …`, `[dev/pkgs] …`, `[docs] …`.
- Common scopes: nixpkgs, flake/*, core/*, hosts/<hostname>, dev/*, cli/*, hardware/*, media/*, servers/*, modules/*, packages/*, docs, ci, refactor.
- Subjects must be in imperative mood, short and specific, without a trailing period.
- Examples:
  - `[media/audio] Add TidalCycles live-coding stack`
  - `[hosts/odin] Tune cooling profile`
  - `[docs] Document audio creation stack`
