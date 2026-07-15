# zen-to-vivaldi-profile-migration - Work Plan

## TL;DR (For humans)
<!-- Fill this LAST, after the detailed plan below is written, so it summarizes the REAL plan. -->
<!-- Plain English for a non-engineer: NO file paths, NO todo numbers, NO wave/agent/tool names. -->

**What you'll get:** A single command `zen-profile-migrate` that transfers your Zen Browser profile (bookmarks, cookies, and guidance for passwords/history) to Vivaldi — with a safety backup of your current Vivaldi data before any changes.

**Why this approach:** Vivaldi already imports bookmarks/passwords/history from Firefox natively (GUI step). For cookies — which can't be imported natively — we decrypt them directly from Firefox's encrypted database and write them to Vivaldi's format. Python + NSS libraries handle the crypto; no external unreviewed tools.

**What it will NOT do:** Transfer extensions (Firefox addons don't work in Chromium), migrate browser settings, or automate the Vivaldi GUI import step. Your Zen profile stays untouched.

**Effort:** Medium
**Risk:** Medium - cookie migration touches encrypted browser databases; profile is backed up before any write
**Decisions to sanity-check:** Cookies migrate via direct Python/NSS implementation (FF2Chrome not found); Vivaldi must be closed during migration; import of passwords/history is manual via Vivaldi GUI.

Your next move: approve plan (say "yes" or "/start-work"). Full execution detail follows below.

---

> TL;DR (machine): Medium effort, Medium risk. New zen-profile-migrate script: bookmarks (existing export), cookies (Python+NSS direct transfer), passwords/history (Vivaldi GUI import with instructions), plus backup + report.

## Scope
### Must have
- `zen-profile-migrate` shell script (orchestrator): find profiles, check both Zen and Vivaldi are closed, backup Vivaldi profile, run migration stages, print report
- Cookie migration: Python script reading Firefox `cookies.sqlite` + `key4.db`, decrypting via NSS, writing to Chromium `Cookies` SQLite
- Reuse existing `zen-bookmarks-export` for bookmarks (call it internally)
- Post-migration report: what was migrated automatically, what needs manual steps (passwords/history via Vivaldi GUI, extensions reinstall)
- NixOS module: new script in `zen-migrate.nix`, dependencies (python3, sqlite, nss), installed to `environment.systemPackages`
- Safety: backup tarball of Vivaldi profile before any modification

### Must NOT have (guardrails, anti-slop, scope boundaries)
- Extension migration (impossible: different extension ecosystems)
- Browser settings/preferences migration
- Automated Vivaldi GUI manipulation (xdotool/ydotool — unreliable, fragile)
- systemd service/timer (one-shot operation only)
- Modifications to vivaldi.nix, default.nix, browsing.nix, or any other existing module
- Interactive prompts — script must be non-interactive (accept `--profile`, `--yes` flags)
- Deleting Zen profile (source data preserved)

## Verification strategy
> Zero human intervention - all verification is agent-executed.
- Test decision: tests-after — migration scripts will be tested against synthetic Firefox/Chromium SQLite databases
- Evidence: .omo/evidence/task-<N>-zen-to-vivaldi-profile-migration.<ext>

## Execution strategy
### Parallel execution waves
> Target 5-8 todos per wave. Fewer than 3 (except the final) means you under-split.

- **Wave 1** (sequential): Cookie migration Python core (reading, decrypting, writing) — sequential because each step depends on the previous
- **Wave 2** (parallel): Main orchestrator script + NixOS module wiring — T4/T5 are independent of T1-T3 (orchestrator just calls named scripts by contract)
- **Wave 3** (sequential): Integration testing — synthetic DBs → verify cookie integrity
- **Wave 4** (parallel): Final verification wave (F1-F4)

### Dependency matrix
| Todo | Depends on | Blocks | Can parallelize with |
| --- | --- | --- | --- |
| T1 (Cookie read) | nothing | T2 | — |
| T2 (Cookie decrypt) | T1 | T3 | — |
| T3 (Cookie write) | T2 | T6 | — |
| T4 (Orchestrator script) | nothing | T6 | T5 |
| T5 (NixOS module) | nothing | T6 | T4 |
| T6 (Integration + report) | T3, T4, T5 | F1-F4 | — |

## Todos
> Implementation + Test = ONE todo. Never separate.
<!-- APPEND TASK BATCHES BELOW THIS LINE WITH edit/apply_patch - never rewrite the headers above. -->
- [x] 1. Implement Firefox cookie reading from cookies.sqlite
  What to do / Must NOT do: Read `cookies.sqlite` from Zen profile, extract host, name, value, path, expiry, is_secure, is_httponly, creationTime, sameSite. Firefox stores cookies in TWO columns: `value` (plaintext, populated for cookies set during current browser session — typically empty for most persistent cookies) and `encryptedValue` (always NSS-encrypted BLOB — this is the PRIMARY storage for persistent cookies). Prefer `value` when non-empty; fall back to `encryptedValue` for T2 decryption. **In practice, 95%+ of cookies will need decryption** — the `value` column is an in-memory cache, not persistent storage. Must NOT attempt decryption in this step — just raw read. Mark each record with `needs_decryption: true/false`. Handle schema variance: use `PRAGMA table_info(moz_cookies)` to detect available columns; skip missing ones gracefully (e.g., `sameSite` added in Firefox 60+). Write a Python script `zen-cookie-read` that takes profile path and outputs JSON of cookie records.
  Parallelization: Wave 1 | Blocked by: nothing | Blocks: T2
  References: modules/user/nix-maid/web/zen-migrate.nix:59-60 (profile paths); Firefox cookies.sqlite schema: `moz_cookies` table (baseDomain, name, value, encryptedValue, host, path, expiry, creationTime, isSecure, isHttpOnly, sameSite)
  Acceptance criteria (agent-executable): `python3 zen-cookie-read --profile /path/to/test/profile > /tmp/cookies.json && [ -s /tmp/cookies.json ] && python3 -c "import json; d=json.load(open('/tmp/cookies.json')); assert len(d)>0; assert all(k in d[0] for k in ['host','name','value','path'])"`
  QA scenarios (name the exact tool + invocation): happy: read cookies from test profile → valid JSON with expected fields; schema-variant table with missing sameSite → graceful skip, no crash. failure: missing cookies.sqlite → clear error message, exit 1. Evidence .omo/evidence/task-1-zen-to-vivaldi-profile-migration.json
  Commit: Y | feat(web/zen): add cookie reader for Zen profile migration

- [x] 2. Implement NSS decryption of cookie values via key4.db
  What to do / Must NOT do: Decrypt `encryptedValue` from cookies.sqlite using NSS key4.db for cookies where the plaintext `value` column was empty. Use `pkgs.nss` for `libnss3.so`. Python calls via `ctypes`. Must NOT hardcode encryption key — use NSS key database. Must handle both NSS db formats (cert8.db/key3.db vs cert9.db/key4.db). **Master password check**: before calling `PK11_Authenticate`, check `PK11_NeedLogin(slot)` — if true, exit with error "NSS master password is set. Cannot decrypt cookies non-interactively. Disable master password in Zen first." Cookies already in plaintext (from T1 `value` column) pass through unchanged.
  Parallelization: Wave 1 | Blocked by: T1 | Blocks: T3
  References: NSS library in nixpkgs: `pkgs.nss`; Firefox NSS key storage: profile directory contains `key4.db` (or `key3.db` for older profiles)
  Acceptance criteria (agent-executable): `python3 zen-cookie-decrypt --profile /path/to/test/profile --input /tmp/cookies.json > /tmp/decrypted.json` → decrypted values are plaintext ASCII/UTF-8 strings
  QA scenarios: happy: decrypt known test cookie → plaintext value matches expected. happy: master password not set → PK11_NeedLogin returns false, auth proceeds. failure: missing key4.db → clear error "NSS key database not found". failure: master password set → exit with clear error about non-interactive limitation. Evidence .omo/evidence/task-2-zen-to-vivaldi-profile-migration.json
  Commit: Y | feat(web/zen): add NSS cookie decryption for Zen→Vivaldi migration

- [x] 3. Implement Chromium cookie writing to Vivaldi Cookies database
  What to do / Must NOT do: Write decrypted cookies to `~/.config/vivaldi/Default/Cookies` SQLite database. Chromium schema: `cookies` table (creation_utc, host_key, name, value, path, expires_utc, is_secure, is_httponly, has_expires, persistent, priority, encrypted_value, samesite, source_scheme). Must shut down Vivaldi before writing. **Atomic write**: write to a temporary `Cookies.new` file in the same directory, verify with `PRAGMA integrity_check`, then `os.rename('Cookies.new', 'Cookies')`. This prevents corruption if the script crashes mid-write. Must NOT leave partial writes. If Vivaldi profile dir doesn't exist (never launched), create it and a fresh empty Cookies DB.
  Parallelization: Wave 1 | Blocked by: T2 | Blocks: T6
  References: Chromium Cookies schema — see field mapping table below.
  Field mapping (Firefox → Chromium):
  | Firefox moz_cookies | Chromium cookies | Transform |
  |---|---|---|
  | host (may have leading dot) | host_key | Strip leading dot |
  | name | name | Copy as-is |
  | value (decrypted) | value | Copy as-is |
  | path | path | Copy as-is |
  | expiry (Unix epoch sec) | expires_utc | (expiry + 11644473600) * 1000000 (Unix→1601 epoch μs) |
  | isSecure | is_secure | Copy 0/1 as-is |
  | isHttpOnly | is_httponly | Copy 0/1 as-is |
  | sameSite (0=unspec, 1=lax, 2=strict) | samesite (-1=unspec, 0=none, 1=lax, 2=strict) | **Pair-aware**: `sameSite=0, isSecure=0` → `-1` (unspecified); `sameSite=0, isSecure=1` → `0` (None — cross-site secure cookie; critical for OAuth/SSO); `sameSite=1` → `1`; `sameSite=2` → `2`. Without the `isSecure` check, SameSite=None cookies are silently lost. |
  | creationTime (μs since Unix epoch) | creation_utc | `(creationTime/1000000 + 11644473600) * 1000000`. T1 must also read `creationTime` from `moz_cookies`. |
  | (none) | has_expires | 1 if expiry > 0, else 0 |
  | (none) | persistent | 1 |
  | (none) | priority | 1 (MEDIUM) |
  | (none) | source_scheme | 2 (SCHEME_UNSET) |
  | (none) | source_port | -1 (PORT_UNSET) |
  | (none) | encrypted_value | See "Encrypted value strategy" below |
  Encrypted value strategy: Chromium's fallback from `encrypted_value` to `value` is being deprecated (already removed in Edge 120+). Preferred approach: detect OSCrypt mode on Linux. If no keyring is available (plaintext "v10" mode), write to `encrypted_value` using the v10 format ("v10" prefix + XOR'd plaintext with hardcoded key "peanuts"). If keyring IS available, write plaintext to `value` (with empty `encrypted_value`) and let Chromium re-encrypt on next start — this is the fallback for now. Post-migration verification (T6) must confirm cookies survive Vivaldi restart regardless of path taken.
  Acceptance criteria (agent-executable): `python3 zen-cookie-write --profile /tmp/test-vivaldi --input /tmp/decrypted.json && sqlite3 /tmp/test-vivaldi/Cookies "SELECT COUNT(*) FROM cookies"` → count > 0. Then verify: `sqlite3 /tmp/test-vivaldi/Cookies "SELECT host_key, name, value, expires_utc, samesite FROM cookies LIMIT 1"` shows correct transformed values.
  QA scenarios: happy: write 3 decrypted cookies to test Chromium profile → cookies table has 3 rows with correct transformed values; SameSite=None cookie (sameSite=0, isSecure=1) maps to samesite=0 in output. happy: no pre-existing Vivaldi profile → creates directory + empty Cookies DB, then writes atomically. failure: Vivaldi running → refuse with "Vivaldi is running, close it first". Evidence .omo/evidence/task-3-zen-to-vivaldi-profile-migration.json
  Commit: Y | feat(web/zen): add Chromium cookie writer for Zen→Vivaldi migration

- [x] 4. Build main orchestrator script `zen-profile-migrate`
  What to do / Must NOT do: A `writeShellApplication` shell script that: (1) parses `--profile`, `--yes`, `--help`, `--dry-run` flags; (2) checks Zen/Firefox is not running (`pgrep -f zen` — exit 1 with "Zen browser is running. Close it first."); (3) auto-detects Zen profile (reuse logic from zen-migrate.nix:54-84); (4) checks Vivaldi is not running (`pgrep -f vivaldi` — matches vivaldi-bin, vivaldi-stable, and any --type= subprocesses); (5) creates backup tarball at `$HOME/zen-to-vivaldi-backup-$(date +%Y%m%d-%H%M%S).tar.gz` of `~/.config/vivaldi/Default/`, excluding cache dirs and WAL/SHM files: `--exclude='Cache' --exclude='Code Cache' --exclude='GPUCache' --exclude='DawnCache' --exclude='*.wal' --exclude='*.shm'`; (6) calls `zen-bookmarks-export`; (7) calls Python cookie pipeline (T1→T2→T3 scripts); (8) prints a post-migration report (see report content spec below). Must NOT be interactive: omitting `--yes` → exit 2 with "Use --yes to confirm migration". Must NOT delete Zen profile.
  Post-migration report must include: (a) count of bookmarks exported + output file path; (b) count of cookies migrated (split: plaintext vs NSS-decrypted); (c) manual step: passwords — "Export from Zen: about:logins → Export Logins → CSV. Import to Vivaldi: launch with `vivaldi --enable-features=PasswordImport`, go to vivaldi://password-manager/settings → Import"; (d) manual step: history/autofill — "Vivaldi → vivaldi://settings/importData → Firefox → check History, Autofill"; (e) manual step: extensions — "Reinstall from Chrome Web Store: uBlock Origin, SurfingKeys (already configured in /etc/nixos)"; (f) backup location + restore command: "tar xzf <backup-file> -C $HOME/.config/vivaldi/"; (g) Zen profile left untouched at <detected path>.
  Parallelization: Wave 2 | Blocked by: nothing | Blocks: T6
  References: modules/user/nix-maid/web/zen-migrate.nix:10-233 (existing `writeShellApplication` pattern, profile detection, HTML escaping); modules/user/nix-maid/web/vivaldi.nix:19-22 (Vivaldi package name)
  Acceptance criteria (agent-executable): `zen-profile-migrate --help` → shows usage with all flags (--profile, --yes, --help, --dry-run) and examples. `zen-profile-migrate --dry-run --profile /some/path` → prints planned actions with file paths, exits 0. `zen-profile-migrate --profile /nonexistent` → clear error, exit 1. `zen-profile-migrate` (no flags) → exit 2 with "Use --yes to confirm".
  QA scenarios: happy: run with --dry-run on a valid profile → prints planned actions (including backup path, bookmark output, cookie count estimate), exits 0. failure: Zen running → "Zen browser is running. Close it first.", exit 1. failure: Vivaldi running → "Vivaldi is running. Close it first.", exit 1. failure: no --yes → exit 2 with confirmation message. Evidence .omo/evidence/task-4-zen-to-vivaldi-profile-migration.txt
  Commit: Y | feat(web/zen): add zen-profile-migrate orchestrator for full profile migration

- [x] 5. Wire NixOS module dependencies and systemPackages
  What to do / Must NOT do: Extend `modules/user/nix-maid/web/zen-migrate.nix` to: (1) add `python3` (with `sqlite3` stdlib) and `nss` as `runtimeInputs`; (2) export `LD_LIBRARY_PATH` in the shell wrapper to include `${pkgs.nss}/lib` so Python's `ctypes.CDLL("libnss3.so")` can find the library at runtime; (3) package the Python cookie scripts as part of the derivation; (4) add `zen-profile-migrate` to `environment.systemPackages`. Must NOT modify `vivaldi.nix`, `default.nix`, or `browsing.nix`. Must keep existing `zen-bookmarks-export` intact.
  Parallelization: Wave 2 | Blocked by: nothing | Blocks: T6
  References: modules/user/nix-maid/web/zen-migrate.nix:1-242 (current module structure, `writeShellApplication`, `runtimeInputs`, `environment.systemPackages`); modules/user/nix-maid/web/vivaldi.nix:1-88 (Vivaldi module pattern for reference)
  Acceptance criteria (agent-executable): `nix eval .#nixosConfigurations.odin.config.environment.systemPackages --apply 'xs: builtins.any (x: x.pname or "" == "zen-profile-migrate") xs'` → `true`
  QA scenarios: happy: `nixos-rebuild dry-build` succeeds, `which zen-profile-migrate` finds the script after switch; Python can `ctypes.CDLL("libnss3.so")` (LD_LIBRARY_PATH set correctly). failure: missing nss dependency → build fails with clear error about nss. Evidence .omo/evidence/task-5-zen-to-vivaldi-profile-migration.txt
  Commit: Y | feat(web/zen): wire zen-profile-migrate into NixOS module with Python+NSS deps

- [x] 6. Integration test: full migration pipeline on synthetic data
  What to do / Must NOT do: Create a test harness with synthetic Firefox `cookies.sqlite` + `key4.db` (using NSS tools to create known cookies including a SameSite=None cookie) and empty Vivaldi `Cookies` DB. Run `zen-profile-migrate --profile /tmp/test-zen --yes`. Verify: backup tarball created, cookies in Vivaldi DB match source (including SameSite mapping), report printed with all sections. Must NOT use real browser profiles. Must clean up temp dirs.
  Parallelization: Wave 3 | Blocked by: T3, T4, T5 | Blocks: nothing
  References: T1-T5 outputs; NSS `certutil` for creating test key databases; `sqlite3` for creating synthetic `cookies.sqlite` with known encrypted values
  Acceptance criteria (agent-executable): Full pipeline run on synthetic data → exit 0, backup tarball exists at `$HOME/zen-to-vivaldi-backup-*.tar.gz` and is non-empty (does not contain Cache/ dirs), Vivaldi test Cookies DB has expected cookie count, report mentions all migrated data types AND contains actionable manual-step instructions (Vivaldi import URL, backup restore command, extension names). SameSite=None cookie maps correctly (samesite=0 in Chromium DB).
  QA scenarios: happy: synthetic Zen profile with 5 cookies including SameSite=None → 5 cookies in Vivaldi DB after migration, SameSite mapping correct, report has import URL and restore command. happy (OSCrypt): after migration, launch Vivaldi against test profile → Vivaldi starts without errors, cookies survive restart (verify via sqlite3 that encrypted_value is now non-empty — OSCrypt re-encrypted). failure: corrupted key4.db → script exits with clear error, does not modify Vivaldi profile. failure: Zen running → orchestrator blocks at step 2 with clear error. Evidence .omo/evidence/task-6-zen-to-vivaldi-profile-migration.log
  Commit: Y | test(web/zen): add integration test for zen-profile-migrate pipeline

## Final verification wave
> Runs in parallel after ALL todos. ALL must APPROVE. Surface results and wait for the user's explicit okay before declaring complete.
- [x] F1. Plan compliance audit — confirm every todo is done, every acceptance criterion met
- [x] F2. Code quality review — check Nix style (alejandra), no dead code, consistent patterns
- [x] F3. Dry-run verification — run `zen-profile-migrate --dry-run` against a real Zen profile (if available), verify all migration stages listed without errors
- [x] F4. Scope fidelity — confirm no extra files were modified, no vivaldi.nix or other module changes

## Commit strategy
Each todo is one commit:
1. `[web/zen] Add cookie reader for Zen profile migration`
2. `[web/zen] Add NSS cookie decryption for Zen→Vivaldi migration`
3. `[web/zen] Add Chromium cookie writer for Zen→Vivaldi migration`
4. `[web/zen] Add zen-profile-migrate orchestrator for full profile migration`
5. `[web/zen] Wire zen-profile-migrate into NixOS module with Python+NSS deps`
6. `[test/zen] Add integration test for zen-profile-migrate pipeline`

## Success criteria
1. `zen-profile-migrate` is installed and visible in `PATH`
2. Running `zen-profile-migrate --dry-run` on a machine with a Zen profile prints planned actions without modifying anything
3. Full migration on synthetic data transfers cookies correctly, including SameSite=None mapping
4. Backup tarball is created before any Vivaldi profile modification (cache dirs excluded)
5. Vivaldi or Zen is detected as running → migration refuses to proceed
6. Post-migration report clearly states what was done and what needs manual steps
7. NSS master password → graceful error exit (non-interactive constraint preserved)
8. Atomic cookie DB write (temp file + integrity check + rename)
