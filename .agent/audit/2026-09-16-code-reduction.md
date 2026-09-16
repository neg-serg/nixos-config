# Code-reduction survey — 2026-09-16

Research first, then the log of the pass it triggered. Six read-only zones ran as parallel subagents
— **modules/ (nix)**, **quickshell (QML/JS)**, **nvim + files/**, **packages/ + scripts/**, **flake/
\+ hosts/ + lib/ + Justfile + dsh scaffold**, plus a mechanical pass run by the parent. Raw zone
reports: `/tmp/refactor-*.md` (ephemeral); this file is the durable summary. Companion:
`2026-09-16.md` (the dead-code audit).

## Baseline (measured)

- **93 529 lines** of code in 988 files (~75 000 excluding comments and blank lines):
  `files/quickshell` 26 717 · `modules/` 16 943 (317 nix files) · `files/nvim` 13 771 · `hosts/odin`
  3 683 · `modules/system` 3 349 · `files/surfingkeys.js` 2 137.
- **Literal duplication is small.** Of 65 108 ten-line windows, 477 (0.7%) repeat in another file;
  by area: `scripts/dev` 4.5%, `files/gui` 4.3%, `nvim` 1.5%, `quickshell` 0.8%, `modules/user`
  0.6%. Counting each shared window as one duplicated *line* (not ten), cross-file literal
  duplication is roughly **1 300 lines**, and ~770 of them are a single pair of files.
- Therefore the lever is **boilerplate and over-explicit data**, not copy-paste. Several first
  estimates had to be corrected downwards (see "Corrections" below); the honest total is **~3 000
  lines identified**, of which **~800–1 000 are low-risk**.

## Corrections to first-pass numbers

| Claim (first pass)                                        | Reality (re-verified)                                               |
| --------------------------------------------------------- | ------------------------------------------------------------------- |
| `Holidays.js` ↔ `Weather.js` ≈ 410 duplicate lines        | 50–67                                                               |
| nvim `native.lua` ↔ `native_pick.lua` ≈ 430 lines         | 315 exact / ~480 including structural; `open_window` ratio 0.97     |
| `Bar.qml` ↔ `AccentSampler.js` ≈ 110 lines                | 38–40                                                               |
| `NotificationManager.qml` pair ≈ 180 lines                | 58 (files are 99 + 79 lines)                                        |
| `check-dsh-statusline.sh` ↔ `check-dsh-worktree.sh` ≈ 160 | 42 covered / 32 unique                                              |
| `modules/` "187 files", `modules/system` "59"             | 112 and 52 (the earlier count included non-nix files)               |
| systemd units "22 hand-rolled vs 16 helper calls"         | 44 named sites in total, only 10 through helpers, ~34 hand-rolled   |
| `gen-codebase` and `docs-modules` duplicate a tree walk   | no: `docs-modules` is `nixosOptionsDocumentation`, there is no walk |

## Implemented so far

| Change                                                                                                                                                                           | Δ lines            | Evidence                                                                                                                                                                                                                                 |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `files/shell/f-sy-h/neg.ini` is now the single theme source; `theme.ini` is generated in the store                                                                               | −785 net           | md5 `c59dbd29…` (14 134 B) identical through both an independent python transform and `nix-instantiate --eval` on the same `replaceStrings`; the parent reproduced the transform and compared it byte-for-byte against the deployed file |
| shared `packages/lib/mkMeta.nix` for the package meta boilerplate                                                                                                                | −52 net (63 files) | field-by-field comparison against HEAD (63/63, files byte-identical outside `meta`), real `nix eval pkgs.<pkg>.meta` before/after (63/63), and 18 flake-exposed packages re-checked                                                      |
| table-driven `scripts/dev/check-all-syntax.sh`                                                                                                                                   | −69                | sha256 of the full output identical before/after, empty diff, and synthetic failure / missing-tool runs produce the same text and exit codes                                                                                             |
| record tables → per-table constructors (kitty, rmpc, mpv, yazi, zellij, adguard, login-limit)                                                                                    | −637               | `nixfmt --check` + `nix-instantiate --parse` per file, and a JSON dump of every table identical before/after (this check caught a missing-parens bug in argument position)                                                               |
| `files/quickshell` tier A: 9 folds + 3 greeter bugs                                                                                                                              | −314               | `qmllint` 6.11.1 exit 0 on every `.qml`; runtime models for the accent sampler (2000 cases bit-identical), the wheel fix, the monitor geometry                                                                                           |
| `files/gui/swayimg/init.lua` → `act()` factory                                                                                                                                   | −164               | mock-swayimg harness dumps "mode/key → command + API trace" for all 189 handlers; diff before/after is empty                                                                                                                             |
| `flake/devshells` → `mkDevShell` + `genAttrs` registry                                                                                                                           | −113 net           | `nix eval .#devShells.x86_64-linux` returns the same 26 names; every shell's argument set byte-identical                                                                                                                                 |
| nvim `lusty/tests/harness.lua` + 16 suites                                                                                                                                       | −114 net           | all 16 suites `rc=0` under `nvim --clean --headless`, stdout byte-identical to the pre-change baseline, negative paths still SKIP                                                                                                        |
| `packages/lib/mkScQuark.nix` for 17 SC-quark packages                                                                                                                            | −82 net            | per-package equality of pname/version/fetcher/hash/installDir/installPhase/meta, re-proved by a strict eval with mock fetchers                                                                                                           |
| `lib/opts.nix` → one `mkTypedOpt` + five one-liners                                                                                                                              | −68                | `nix-instantiate --parse`, `nixfmt --check`                                                                                                                                                                                              |
| `files/fastfetch/make_blizzard.py` → one `_diffuse(g, kern, divisor)`                                                                                                            | −40                | sha256 of all four dither outputs (fs/atkinson/sierra/stucki, seed 7) identical before/after                                                                                                                                             |
| `files/nvim/lua/scripts/beacon.lua` → one `__render(list_on)` + two wrappers                                                                                                     | −32                | `loadfile` OK; the three differences between the twins were mapped one by one (guard, extra-space branch, pcall) and the renderers have no external callers                                                                              |
| dead `files/mpv/script-opts/osc.conf` + its deploy block                                                                                                                         | −25                | `mpv.conf:40` sets `osc=no`; `nix-instantiate --parse` on the module                                                                                                                                                                     |
| shared `scripts/dev/lib.sh` + `.agent/scripts/lib.mjs`                                                                                                                           | −20 net            | `shellcheck -S warning`, `osh -n`, both dsh gates byte-identical stdout, argv vectors identical                                                                                                                                          |
| bug fixes: `hyprwhspr/status.js` (`detail` out of scope), `hyprland.lua` (duplicate `XF86AudioMute`), stale `dsh-task-resume-info` test (fake session lacked `snapshotEvents()`) | ~0                 | `node --check`, `lua loadfile`, the test now reports 10 passed / 0 failed                                                                                                                                                                |
| shared `test-harness.mjs` for the small dsh tests — **tried, reverted**                                                                                                          | 0                  | 7 tests −38 lines, harness +37 → net −1                                                                                                                                                                                                  |

### Last round (parallel writers)

Eleven items landed through three disjoint-scope writers plus a parent pass; every row below was
re-verified by the parent against the pre-change version before committing.

| Change                                                                | Δ lines           | Evidence (parent's own runs)                                                                                                                                                                                                                                      |
| --------------------------------------------------------------------- | ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `packages/dsh/lib/patchlib.py` for the three count-assert patch loops | −25 dup (+32 net) | `py_compile` ×4, `nix-instantiate --parse`, `shellcheck`; nine-scenario equivalence harness (one/zero/two matches × three message styles) — files, stdout, stderr and rc identical; the build is the only caller (`PYTHONPATH=@PATCHLIB_DIR@` at all three sites) |
| `packages/local-bin/bin/_localbin.sh` for the need/die/usage preamble | −17 dup (+36 net) | sh/bash/zsh `-n`, `shellcheck` clean, 31 run comparisons (20 help variants, 11 stripped-PATH dependency paths) with identical stdout/stderr/rc; `gen-codebase --stdout` byte-identical to HEAD                                                                    |
| `neg.mkDirEntries` for the two `~/.local/bin` entry tables            | −20               | both entry sets and rendered files unchanged; `_localbin.sh` rides along because the directory is installed wholesale                                                                                                                                             |
| Justfile `repo_root :=` variable                                      | −8                | `just --list` and `--dry-run` render; the `\|\| pwd` fallback kept (a recipe run evaluates the backtick even when `--list` does not)                                                                                                                              |
| `files/shell/f-sy-h/fsyh_theme_common.py`                             | −3 net            | 14 stdout comparisons byte-identical (real 61-line theme + synthetic input × 7 flag sets); `--write` result and `.bak` identical, second run silent                                                                                                               |
| shared `_fzf_fd` in `files/shell/zsh`                                 | −5                | `zsh -n`; fd listing (9 entries) and inserter candidates (4) plus the picker result identical on nine sampled inputs                                                                                                                                              |
| mpv `[audio-osd]` for the four audio extension profiles               | 0                 | `mpv --show-profile=extension.flac` resolves the shared profile and prints the same `term-osd-bar` options; the `[extension.a\|b]`, comma and space forms are proven not to match                                                                                 |
| Vivaldi: four oneshot pref scripts (146) → `vivaldi-prefs.py` (144)   | −2 net            | seven fixtures (empty, minimal, both `actions` shapes, already-correct, the real 371 KB profile, missing file) with identical JSON bytes, stdout, stderr and rc                                                                                                   |
| nvim `lusty/native_core.lua` shared picker core                       | −139 net          | 99-scenario mock-vim harness, before/after dumps identical (21 531 lines, 0 diff), 16/16 headless smoke, `check-lusty-smoke.sh` exit 0                                                                                                                            |
| `scripts/dev` gates reformatted (fmt drift left by `b84d277a0`)       | 0                 | `nix fmt` idempotent afterwards; whitespace only (248 lines)                                                                                                                                                                                                      |

Gate results on the committed tree: `just lint` exit 0, `just check` exit 0, `nixos-rebuild switch`
exit 0. Two of the changes above were *found* by verification rather than written by a writer:
`qr`'s `-h` range had been pushed onto implementation text by the new source line (help now prints
exactly its header block), and `check-osh-syntax.sh` printed four `head: cannot open …` errors for
the Vivaldi scripts that were deleted but not yet staged.

Running total since `b3e8f158b` (the dead-code audit commit): **37 commits, 280 files, +3 529 / −6
761 → net −3 232 lines.** The reduction is coarser than the original estimate because the survey
counted *duplication removed*, while a shared, documented module also adds lines; the sections below
keep both numbers where they differ.

## Ranked ideas

Savings are lines removed; "risk" is the chance of changing behaviour or looks; "effort" S ≤ 30 min,
M ≤ 2 h, L > 2 h.

### Tier 1 — low risk, recommended first

| #   | Area       | Idea                                                                                                                                                                                                                                                                                                                                                             | Save    | Risk    | Effort |
| --- | ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | ------- | ------ |
| 1   | nvim       | Shared `lua/lusty/tests/harness.lua`: `wait_until` is defined 11×, `assert_eq` 3×, the `executable('lusty')` guard 14×, the `package.path` preamble 16×                                                                                                                                                                                                          | 170–200 | low     | S–M    |
| 2   | quickshell | Nine tier-A folds: `_sampleAccent` → `Helpers/AccentSampler.js` (38–40), one HTTP/TTL module for `Holidays`+`Weather` (50–67), inline components in `ScreenshotToast`/`Music` (57–61), `Repeater` in `SystemMonitorCapsule`/`SystemMonitorPopup`/`Calendar` (174–198), `CustomTrayMenu`↔`SubmenuHost` key body (18), delete the no-op `PanelIconButton.qml` (19) | 350–400 | low     | M      |
| 3   | infra      | `mkDevShell` for `flake/devshells/*.nix` (193 of 532 lines are skeleton, 27 hand-written import lists)                                                                                                                                                                                                                                                           | 110–150 | low–med | M      |
| 4   | infra      | One `test-harness.mjs` for the 11 small `dsh-*/test.mjs` (the 4 large harnesses and `dsh-snapcompact` stay)                                                                                                                                                                                                                                                      | 90–110  | low     | S–M    |
| 5   | lib        | `lib/opts.nix`: five factories are one 16-line body ×5 → `mkTypedOpt` (85 of 139 lines)                                                                                                                                                                                                                                                                          | 68      | low     | S      |
| 6   | scripts    | Shared harness for `scripts/dev/*.sh` (`assert`/`check`/footer, `REPO_ROOT` ×9, skip-warning ×8) and `.agent/scripts/lib.mjs` (`parseArgs` ×3, `chat()` ×2)                                                                                                                                                                                                      | 55–75   | low     | S–M    |
| 7   | quickshell | Single inline component for the `ScreenshotToast` action delegate and the `Music` transport trio                                                                                                                                                                                                                                                                 | 57–61   | low     | S      |

### Tier 2 — real savings, more churn or medium risk

| #   | Area       | Idea                                                                                                                                                                                                                                                                                                                                                        | Save    | Risk                            | Effort           |
| --- | ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | ------------------------------- | ---------------- |
| 8   | modules    | R1: uniform record tables that `nixfmt` expands to 4–5 lines each (`shells.nix:20` 42 records/263 lines, `media.nix:19` 34/144, `apps/mpv/input.nix:15` 28/115, `cli/yazi.nix:212` 29/164, `hosts/odin/default.nix:17` 20/112, `services/policy.nix:67` 17/96, `security/default.nix:46` 11/68) → per-table constructors; consumers only destructure fields | 510–620 | low behaviour, high style churn | M–L              |
| 9   | packages   | `mkScQuark` for 17 pure `stdenvNoCC` SC-quark packages (729 lines, 14-line skeleton each)                                                                                                                                                                                                                                                                   | ~355    | med–high (17 derivations)       | M–L              |
| 10  | files      | Derive one of the two zsh-syntax themes from the other (`f-sy-h/neg.ini` 807 vs `zsh-native-syntax/theme.ini` 813; `diff` = 12 lines). Needs a generation step wired in `shells.nix`, not a deletion                                                                                                                                                        | 780–795 | medium                          | M                |
| 11  | packages   | meta blocks: 93 blocks / 757 lines (85× `meta = with lib; {`, 84× `maintainers = [ ]`) → one builder                                                                                                                                                                                                                                                        | 180–250 | low                             | M (90-file diff) |
| 12  | modules    | R5: 14 seven-line `default.nix` aggregators → one line each via a new `neg.importDomain ./.`; 13 flat four-line ones by formatting                                                                                                                                                                                                                          | 110–125 | low                             | S                |
| 13  | infra      | `hosts/odin`: 10 oneshot+timer pairs (`notify-*.nix`, `telegram-units.nix`) → `mkOneshotTimer` (55–70); zellij's four `replaceStrings` stages → one `lib.pipe` (27)                                                                                                                                                                                         | 82–97   | medium                          | M                |
| 14  | nvim       | `lusty/native.lua` ↔ `native_pick.lua` shared core (`open_window` 0.97, `width`/`height` 1.00); 11 headless smoke tests to re-run                                                                                                                                                                                                                           | 120–170 | high                            | L                |
| 15  | files      | `gui/swayimg/init.lua`: 98 hand-written `exec(actions …)` closures → one dispatcher                                                                                                                                                                                                                                                                         | 82–184  | medium                          | M                |
| 16  | modules    | R2: `dsh-terminal-plugins.nix:24` — all 27 records have `name == path`; a name list + `map`; keep the roster explicit (no `readDir`)                                                                                                                                                                                                                        | 75–82   | low                             | S                |
| 17  | scripts    | `check-all-syntax.sh`: 7 copies of one skeleton (158 of 175 lines) + the `ERROR`/`head -5`/`fail=1` block ×8 → table-driven driver (it is a `just lint` gate)                                                                                                                                                                                               | 60–70   | medium                          | M                |
| 18  | quickshell | Tier B: `GuardedFileView` for the FileView+JsonAdapter write-guard ×3, greeter↔main `NotificationManager`, greeter slider groove, greeter `Players.qml` art/track wiring                                                                                                                                                                                    | ~250    | medium                          | M                |

### Tier 3 — smaller, still worthwhile

`make_blizzard.py` four dithers → one loop (65–70, verified by webp sha256) · `scripts/beacon.lua`
`__list_render` ≡ `__nolist_render` (45) · picker runners + fuzzy filter in
`native_buffers`/`native_recent` (60–75) · `luasnippets` preambles (65–75) · dsh-plugin-kit: the
byte-identical hash block (`hashline:36-77` ≡ `read-tags:33-72`, comment says it must stay
byte-identical), `sessionCwd` ×3, `pluginMessage` ×11 (~100, medium — packaging traps) ·
`patchlib.py` for the count-assert loop ×3 (20–25) · `gen-codebase` `build_*` skeleton ×5 (20–30) ·
`vp-*`-style pickers, hunting, and misc (25–30) · `Justfile` `repo_root` ×13 → one top-level
variable (~12, verify lazy backtick evaluation) · `neg.readFile` helper and dropping redundant
`config.` where `.source` already wraps (17) · `systemdUser` on `config.lib.neg` to delete 9
identical import lines (23, includes two `mkUserService` conversions).

## Explicitly rejected (do not re-propose)

- **Deduping `mkIf cfg.enable` wrappers** — the repo already reverted such a `gate` helper because
  it recursed through the config fixpoint (`modules/core/neg.nix:44-52`).
- **Migrating the ~30 hand-rolled user units to `mkUserService`** — measured shapes differ
  (Environment/Restart/partOf/requires vary per unit); the earlier audit's C6 decision (no forced
  migration) still holds.
- **Shared scaffolding for the 30 dsh plugins** — across all `lib/index.js` exactly one line is
  common (`}`); the `package.json` boilerplate is 13 lines and required by npm. `npm workspaces` and
  a generator conflict with the caretaker, which `cp`s files into the profile.
- **Shared `test-harness.mjs` for the small dsh tests** — implemented and measured, then reverted:
  the seven tests went 309 → 271 lines (−38) while the harness itself is 37 lines, a net of −1. The
  win is structural (one definition instead of seven), not in volume, so it does not pay for the
  indirection. The four large harnesses stay as they are.
- **Unifying `mkBoolOpt`/`mkBool`/`mkEnableOption`**, `package-checks.nix`'s table, `ru-keys`
  (golden-tested), the two `*-tests.nix` harnesses, `importDir` internals, "hosts vs modules" (no
  duplicated logic), `unbound-hosts`/`hardware` (data), merging `apps.nix`+`devshells.nix`.
- **QML idioms** (`Rectangle {` ×122, `anchors.fill: parent` ×118, `Layout.fillWidth` ×77,
  `pragma ComponentBehavior: Bound` ×48) — framework-inherent, not reducible.
- **hyprlock themes** (kept on purpose, see the audit), the Neg Dark palette copies (0 lines to
  save; they are linked by `GENERATED` markers), `kitty/**`, `files/art/**`, nvim `ftplugin/**`,
  `hyprland.lua` (zero duplication).

## Bugs and dead code found while researching (separate track)

- `files/quickshell/greeter/notifications/DaemonNotification.qml:22-24` — empty `handleDismiss()`;
  the main tree calls `daemon.discard()` there with a comment that an empty body leaves a dangling
  backer (the same bug was fixed only in the main copy).
- `files/quickshell/greeter/bar/audio/VolumeSlider.qml:86-90` — the wheel handler assigns
  `__wheelValue` and immediately resets it to `-1`, so the wheel does nothing.
- `files/quickshell/Bar/Modules/Media.qml:469-471` vs `:545` — the title is joined differently for
  the width measurement and for rendering.
- `files/gui/vicinae-extensions/hyprwhspr/status.js:42` — `detail` was referenced outside its scope
  on the success path, so the promise never settled (the callback throws asynchronously and the
  outer `try` cannot see it). Fixed: the success path reports `detail: ""`, matching the UI, which
  renders the row only when the field is non-empty.
- `files/gui/hypr/hyprland.lua:229,232` — `XF86AudioMute` was bound twice with the same two commands
  in opposite order. Fixed: the duplicate earlier bind is gone; the survivor matches the ordering of
  the volume keys.
- `files/nvim/luasnippets/go.lua:6` — **not a bug**, checked: the `require("settings.luasnip.util")`
  is wrapped in `pcall` with stub fallbacks, so the snippets load either way.
- Unreachable/unused: `Helpers/Weather.js` `_normalizeWttrIn` + `_WWO_TO_WMO` (~103),
  `Widgets/SidePanel/Music.qml:120-252` (flags hardcoded `false`, ~130), `Helpers/Http.js` +
  `HttpCache.js` (no importers), `files/shell/zsh/lazyfuncs/zpcompinit_custom` (removed: the same
  logic lives inline as `_zpcompinit_custom()` in `01-init.zsh:85` and the file is neither in the
  `autoload -Uz` list nor called), and `mpv/script-opts/osc.conf` (dead: `mpv.conf:40` sets
  `osc=no`; removed together with its deploy block in `apps/mpv/scripts.nix`).
- **Two "dead" candidates turned out to be live — checked before deleting, kept:**
  `files/shell/f-sy-h/secondary_theme.zsh` has no in-repo reference, but F-Sy-H sources it at
  runtime from `$FAST_WORK_DIR` (`neg.ini:15` sets `secondary = zdharma`; the plugin executes
  `source $FAST_WORK_DIR/secondary_theme.zsh`), so removing it would break the secondary
  highlighting; and `files/winapps/apps/*/info` (56 near-identical files) are data the winapps
  module reads with `builtins.readFile` and the launcher sources at runtime. The survey's "9 dead
  nvim locales" is not reproducible and is dropped. A trap worth remembering: `rg -rn` means
  *replace*, not recursive — an audit that used it reported names masked as `n.zsh` and concluded
  "no references".

## Process note

A previous audit (`.agent/audit/2026-09-15.md:51`, item B8) records `need()`/`usage()` duplication
as "fixed 7cd0454bb". The tree disagrees: `need()` 11, `usage()` 10, `die()` 5, and there is no
shared lib. Likewise `scripts/dev/check-dsh-sessions.*` is still invoked by nothing. Treat "fixed"
claims in that report as unverified until re-checked.

## How to verify a reduction

1. Behavioural equivalence first: for nix, `nix eval`/`just check` on the affected options; for
   scripts, run the gate and diff its output; for tests, run them; for QML, `qmllint` plus a visual
   check; for the INI theme, `diff` the deployed file against the previous one (must be empty).
1. Land each idea as its own commit with the `[scope]` prefix, so a regression is bisectable.
1. Keep the generators fresh: `just codebase`, `just docs-modules`, then `just docs-guard`.
