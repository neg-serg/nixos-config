# AGENTS usage for this repo

Communication language (hard rule)
- The user (neg) cannot read Chinese at all. NEVER write anything to them in
  Chinese — not in chat replies, not in dsh-ui components, not in commit
  messages, not in any file they will read. Treat this as a hard rule.
- The user's language is Russian. English is acceptable for technical terms,
  code, and identifiers. When in doubt, write in Russian.
- Note: the dsh web GUI itself may contain Chinese strings from plugins
  (e.g. pet.json, dshmarket UI); that is app data, not something we write.
  Do not copy those strings into replies for the user.

Scope
- This AGENTS.md applies to the entire `/etc/nixos` tree.
- Prefer existing module structure (`modules/`, `hosts/`, `modules/user/nix-maid/`, etc.) and follow surrounding style.

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

Builds: substitute = false
- This host is in a region where `cache.nixos.org` is unreliable (blocked/slow), so do NOT rely on binary substitution.
- Always run nix build/eval commands with `--option substitute false` (build from source), e.g.:
  `nix build .#nixosConfigurations.odin.config.system.build.toplevel --dry-run --option substitute false`
- The user's own rebuild binding uses the same flag (`nh os switch /etc/nixos#odin --option substitute false`); keep that convention in any new bindings/scripts.

Commit style
- Use a bracketed scope prefix consistent with existing history, for example: `[media/audio] …`, `[hosts/odin] …`, `[dev/pkgs] …`, `[docs] …`.
- Subjects must be in imperative mood, short and specific, without a trailing period.
- Examples:
  - `[media/audio] Add TidalCycles live-coding stack`
  - `[hosts/odin] Tune cooling profile`
  - `[docs] Document audio creation stack`
