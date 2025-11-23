# AGENTS usage for this repo

Scope
- This AGENTS.md applies to the entire `/etc/nixos` tree.
- Prefer existing module structure (`modules/`, `hosts/`, `home/`, etc.) and follow surrounding style.

Nix style: `pkgs.*` lists
- When adding items like `pkgs.<name>` to `environment.systemPackages` or other package lists, add a short comment after each entry describing what the package is/does, whenever it is not completely obvious.
  - Example: `pkgs.supercollider # SuperCollider IDE and audio engine`
  - Example: `pkgs.haskellPackages.tidal # TidalCycles live-coding library`
- Keep comments concise and focused on purpose/role in the system, not marketing copy.

General guidance
- Keep changes minimal and focused on the feature you are touching.
- Avoid drive-by refactors; mention unrelated issues separately instead of fixing them silently.
- When changing behavior, prefer updating relevant docs under `docs/` or `docs/manual/` as needed.

Commit style
- Use a bracketed scope prefix consistent with existing history, for example: `[media/audio] …`, `[hosts/telfir] …`, `[dev/pkgs] …`, `[docs] …`.
- Subjects must be in imperative mood, short and specific, without a trailing period.
- Examples:
  - `[media/audio] Add TidalCycles live-coding stack`
  - `[hosts/telfir] Tune cooling profile`
  - `[docs] Document audio creation stack`

