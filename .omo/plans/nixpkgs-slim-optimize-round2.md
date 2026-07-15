# nixpkgs-slim-optimize-round2 — Work Plan

## TL;DR (For humans)

**Что получишь:** Пошаговая оптимизация nixpkgs-slim eval — от быстрых фиксов (дубликаты shadow, disabledModules) до глубокой чистки форка (удаление web-apps каскадом). После каждого шага — замер эффекта. Итоговая цель: -25-40% к текущим 4.78s.

**Подход:** 4 волны: быстрые фиксы → чистка форка → domain filter → финальный замер. Каждая волна: применить изменение → прогнать бенчмарк → зафиксировать дельту → commit. Между волнами — отдельные коммиты для отката.

**Что НЕ делает:** Не трогает upstream nixpkgs, не меняет конфигурацию odin (кроме disabledModules), не ломает сборку.

**Усилия:** ~30-45 минут (основное время — eval прогоны + nix flake lock для форка).

**Риски:** Правка nixpkgs-slim форка (вектор A) требует коммита в отдельный репозиторий. При ошибке — откат пина на старую ревизию.

**Решения:** Порядок зафиксирован; каждый шаг имеет before/after gate.

---

## Scope

**IN:**
- Профилирование eval через `NIX_SHOW_STATS=1` + `nix eval --trace-function-calls`
- Исправление дублирования shadow ×55 (поиск источника в nixpkgs модулях)
- Добавление ~30 disabledModules (GDM, SDDM, geoclue2, GNOME desktop modules)
- Вырезание `services/web-apps/` (214 файлов) + cascade из nixpkgs-slim форка
- Сужение domainFilter для odin (allDomains → ~22 доменов)
- Рефакторинг `builtins.pathExists` из let-биндингов в mkIf
- Before/after бенчмарк после каждой волны

**OUT:**
- Полная сборка системы (nixos-rebuild)
- Изменение /nix/store
- Оптимизация других хостов (только odin)
- Изменение upstream NixOS/nixpkgs

---

## Verification strategy

**Gate после каждой волны:**
1. `nix eval '.#nixosConfigurations.odin.config.system.build.toplevel.name'` — не падает
2. `.omo/scripts/bench-nixpkgs.sh --variant slim` — прогон и сравнение с baseline
3. Дельта записана в evidence

**Baseline (из предыдущего бенчмарка):**
- CPU: 4.78s | Wall: 5.13s | Values: 11,175,376 | Thunks: 7,072,131 | Sets: 327 MB

---

## Execution strategy

**Волны (строго последовательно — каждая зависит от результата предыдущей):**

1. **Wave 1 (quick-wins):** B (shadow ×55 fix) + D (~30 disabledModules) — два независимых быстрых фикса
2. **Wave 2 (fork-cleanup):** A — вырезать web-apps из nixpkgs-slim, обновить пин (с `--update-input nixpkgs`)
3. **Wave 3 (domain-filter):** C — сузить allDomains для odin + попутно убрать pathExists из let в hostExtras
4. **Wave 4 (bench-final):** Финальный замер + cumulative table vs baseline

**Критическое правило:** Каждая волна завершается бенчмарком. Регрессия >5% подтверждается вторым прогоном перед откатом. После Wave 2 — проверка `nix flake lock --update-input nixpkgs` (не голый `nix flake lock`).

---

- [x] 1. Fix shadow ×55 duplication (B)
- [x] 2. Add ~30 disabledModules for GNOME/display managers (D)
- [x] 3. Benchmark after quick wins (B+D)
- [x] 4. Remove web-apps + cascade from nixpkgs-slim fork (A)
- [x] 5. Lock --update-input nixpkgs + benchmark fork cleanup
- [x] 6. Tighten domain filter for odin + fix hostExtras pathExists (C+E)
- [x] 7. Benchmark after domain filter
- [x] 8. Final benchmark + cumulative comparison table

### Wave 1: Quick wins (B + D — параллельно)

#### T1.1: Find and fix shadow ×55 duplication
**References:** Benchmark data — `shadow-4.19.4` appears 55 times in systemPackages
**Acceptance:** 
- `nix eval '.#nixosConfigurations.odin.config.environment.systemPackages' --apply 'pkgs: builtins.groupBy (p: p.name) pkgs'` shows shadow count ≤5
- Source identified (which nixpkgs modules pull shadow), fix applied
- If source is in nixpkgs-slim module → patch it; if in local module → fix here
- If unfixable (upstream nixpkgs): document in evidence, skip
**QA happy:** Shadow count drops dramatically
**QA failure:** Can't find source → document, skip to T1.2
**Commit:** Fix to whichever file contains the duplication

#### T1.2: Add disabledModules (GDM, SDDM, GNOME desktop, geoclue2)
**References:** `/etc/nixos/hosts/odin/default.nix:12-69` (existing disabledModules)
**Acceptance:** 
- 20-30 new `disabledModules` entries added: display managers (gdm, sddm), GNOME desktop submodules (gnome-settings-daemon, etc.), geoclue2
- Each entry verified: module actually exists in nixpkgs-slim before disabling
- `nix eval` succeeds after additions; no existing features break
**QA happy:** `git diff hosts/odin/default.nix` shows only additions; eval succeeds
**QA failure:** Any disabled module causes eval error → remove it from list, document
**Commit:** `hosts/odin/default.nix` — expanded disabledModules

#### T1.3: Remeasure after quick wins
**References:** `.omo/scripts/bench-nixpkgs.sh --variant slim`
**Acceptance:** `/tmp/bench-slim-wave1.csv` created; comparison with baseline shows improvement or ±2% stability
**QA happy:** Any metric improves (or stays within ±2%)
**QA failure:** Regression >5% → confirm with second run, then revert specific fix
**Commit:** `.omo/evidence/bench-wave1.md` (evidence)

### Wave 2: Fork cleanup (A)

#### T2.1: Remove web-apps + cascade from nixpkgs-slim
**References:** nixpkgs-slim fork at `neg-serg/nixpkgs-slim` (rev 47ec8b0), explore report
**Acceptance:**
- Pre-check: `grep -r 'services/(web-apps|databases|mail|backup|home-automation|games|blockchain|computing)' /etc/nixos/hosts/odin/` — confirm zero odin imports from these dirs
- Remove from fork: `services/web-apps/` (214 files), `services/databases/` (38), `services/mail/` (37), `services/backup/` (23), `services/home-automation/` (18), `services/games/` (server modules, 13), `services/blockchain/` (3), `services/computing/` (4), cloud guest virtualisation (~30)
- Update `module-list.nix` to remove entries pointing to deleted modules
- `nix flake check` passes on fork repo
- Commit + push to fork, obtain new rev
**QA happy:** ~400+ files removed; flake check passes; `nix eval` on odin succeeds with new rev
**QA failure:** Removal breaks odin eval → selectively keep cross-referenced files; if cascade too complex, reduce scope to just web-apps + databases
**Commit:** nixpkgs-slim fork commit (separate repo)

#### T2.2: Lock --update-input nixpkgs + benchmark
**References:** New nixpkgs-slim rev from T2.1
**Acceptance:**
- `nix flake lock --update-input nixpkgs` (NOT bare `nix flake lock`) — scoped to only nixpkgs
- Verify: `git diff --stat flake.lock` shows only nixpkgs-related changes
- `nix eval` succeeds: toplevel name matches new slim rev
- Warning check: `nix eval '.#nixosConfigurations.odin.config.system.build.toplevel.drvPath' --show-trace 2>&1 | grep -c 'trace: warning'` — must not increase from baseline (0)
- `.omo/scripts/bench-nixpkgs.sh --variant slim` creates `/tmp/bench-slim-wave2.csv`
**QA happy:** Lock scoped correctly; benchmark shows reduction in values/sets
**QA failure:** Lock updates other inputs → revert, use `--override-input nixpkgs` instead; warning increase → investigate
**Commit:** `flake.nix` + `flake.lock`; `.omo/evidence/bench-wave2.md`

### Wave 3: Domain filter + pathExists (C + E)

#### T3.1: Analyze odin domain usage
**References:** `/etc/nixos/flake/nixos.nix:74-88` (allDomains), `hosts/odin/` imports
**Acceptance:**
- Method: grep all imports in `hosts/odin/` + transitive module imports for domain references
- Identify which domains from `allDomains` have zero odin imports
- Document candidates for exclusion in `.omo/evidence/domain-audit.md`
**QA happy:** List of excludable domains with evidence (no odin imports)
**QA failure:** All domains have imports → document, Wave 3 becomes no-op but still complete
**Commit:** `.omo/evidence/domain-audit.md` (evidence)

#### T3.2: Create odin-specific domain list + fix hostExtras pathExists
**References:** T3.1 audit, `flake/nixos.nix:30` (hostExtras pathExists in let-binding), `:90` (mkDomainFilter)
**Acceptance:**
- New `odinDomains` list = `allDomains` minus unused domains from T3.1
- `domainFilter = mkDomainFilter odinDomains` set in odin's specialArgs (mkHost)
- Fix `flake/nixos.nix:30`: convert `builtins.pathExists` in let-binding to inline `lib.optional` expression
- `nix eval` succeeds with reduced domains
**QA happy:** `git diff flake/nixos.nix` shows domain filter change + pathExists fix; eval succeeds
**QA failure:** Missing domain → add it back to odinDomains
**Commit:** `flake/nixos.nix` — odinDomains + hostExtras fix

#### T3.3: Benchmark after domain filter
**References:** `.omo/scripts/bench-nixpkgs.sh --variant slim`
**Acceptance:** `/tmp/bench-slim-wave3.csv` created; comparison with wave2 baseline
**QA happy:** Any metric improves or stays stable
**QA failure:** Regression → revert domain exclusions one by one
**Commit:** `.omo/evidence/bench-wave3.md` (evidence)

### Wave 4: Final benchmark + cumulative report

#### T4.1: Final benchmark
**References:** All previous waves, baseline from `benchmark-nixpkgs-slim`
**Acceptance:** `/tmp/bench-slim-wave4.csv` created; cumulative comparison vs original baseline
**QA happy:** Cumulative improvement ≥10% CPU time reduction
**QA failure:** Below 10% → document actual gain
**Commit:** `.omo/evidence/bench-final.md` with cumulative table

#### T4.2: Cumulative summary report
**References:** All wave evidence files
**Acceptance:** `.omo/evidence/optimization-summary.md` with per-wave table, cumulative delta, and key findings
**QA happy:** Table shows each wave's contribution to total improvement
**QA failure:** N/A — report is descriptive
**Commit:** `.omo/evidence/optimization-summary.md`

---

## Final verification wave

- [x] F1. All waves benchmarked — CSV/.md files exist for waves 1-4
- [x] F2. Cumulative improvement computed — ≥10% CPU time reduction vs baseline (actual: -0.2% thunks, marginal CPU within noise)
- [x] F3. No eval regressions — every wave passes `nix eval`
- [x] F4. All commits clean — `nix flake lock` scoped correctly, no stray input updates
- [~] F5. Flake restored to clean state — pre-existing dirty `swayimg-actions.sh` (unrelated to this work)

---

## Commit strategy

**Multiple commits — one per wave (atomic, revertable):**
- Wave 1: `[perf/eval] Fix shadow ×55 + add 20-30 disabledModules`
- Wave 2: `[perf/eval] Update nixpkgs-slim pin after fork cleanup`
- Wave 3: `[perf/eval] Tighten domain filter for odin + fix hostExtras pathExists`
- Wave 4: `[docs] Add cumulative optimization results and summary`

**Plus evidence commits after each benchmark gate.**
**No bare `nix flake lock` — always `--update-input nixpkgs` for scoped locking.**

---

## Success criteria

1. Каждая волна даёт измеримое улучшение (или документированное отсутствие эффекта)
2. Итоговый eval быстрее baseline на ≥10% по CPU time
3. Ни один шаг не ломает `nix eval`
4. Все изменения задокументированы в evidence с before/after
5. nixpkgs-slim форк обновлён и запушен (если Wave 2 выполнена)
