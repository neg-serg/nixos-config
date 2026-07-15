# benchmark-nixpkgs-slim — Work Plan

## TL;DR (For humans)

**Что получишь:** A/B-сравнение nixpkgs-slim vs upstream NixOS/nixpkgs по скорости eval, памяти и числу создаваемых объектов. Результат — таблица в терминале и markdown-отчёт в `.omo/evidence/`.

**Подход:** Берём эквивалентную upstream-ревизию nixpkgs (по дате текущего пина форка), меряем `nix eval` с `NIX_SHOW_STATS=1` и `time` на обеих версиях (1 холодный + 3 тёплых прогона), считаем дельты.

**Что НЕ делает:** Не билдит систему, не трогает /nix/store, не меняет конфигурацию кроме временной подмены `nixpkgs.url` в `flake.nix`. После бенчмарка восстанавливает исходное состояние.

**Усилия:** ~5 минут wall-time (основное время — eval прогоны по ~5 секунд каждый).

**Риски:** Upstream nixpkgs может не собраться из-за отсутствия whitelist-пакетов в конфиге (тогда eval упадёт — это ожидаемо и будет задокументировано как «цена отсутствия форка»). План захардкожен под хост `odin`.

**Решения:** Все метрики и методология зафиксированы в плане; развилок не осталось.

---

## Scope

**IN:**
- `nix eval '.#nixosConfigurations.odin.config.system.build.toplevel.name'` — один и тот же вызов для обоих nixpkgs
- Метрики: CPU time, wall time, values, thunks, sets (bytes), GC time/fraction, nrAvoided, nrLookups
- Холодный старт (чистый eval-cache) — 1 прогон
- Тёплый старт (закешировано) — 3 прогона
- Автоматический подбор эквивалентной upstream-ревизии по дате
- Таблица сравнения в терминале + markdown
- Восстановление исходного `flake.nix` и `flake.lock` после бенчмарка

**OUT:**
- Полная сборка системы (`nixos-rebuild`)
- Изменение /nix/store
- Замеры для других выражений (drvPath, config)
- Статистический анализ кроме медианы/среднего
- Flamegraph (уже сделан ранее)
- Другие хосты (план захардкожен под `odin`)

---

## Verification strategy

**Happy-path QA (для каждого замера):**
1. Команда возвращает строку вида `"nixos-system-odin-26.11.20260715.XXXXXXXXX"` (rev из заголовка соответствует ожидаемому)
2. `NIX_SHOW_STATS=1` выдаёт валидный JSON со всеми ключами (`cpu`, `values`, `thunks`, `sets`, `gc`)
3. `time` показывает ненулевое wall-time
4. Ни один прогон не падает с ошибкой evaluation

**Failure QA:**
- Если upstream nixpkgs падает на eval → записать ошибку в evidence, отметить как «slim-форк необходим для данной конфигурации»
- Если nixpkgs-slim падает → блокирующая ошибка (регрессия), стоп

**Валидация результатов:**
- Тёплые прогоны должны иметь <10% разброс wall-time между собой
- Если разброс >10% → дополнительный 4-й прогон, исключить outlier

---

## Execution strategy

**Примечание:** `GIT_MASTER=1` — no-op для vanilla git; используется для активации git-master skill в agent-контексте. На результат не влияет.

**Волны:**
1. **Wave 0 (prereqs):** Проверить доступность Nix, flakes, `time`, Python
2. **Wave 1 (prepare):** Найти эквивалентную upstream-ревизию, написать скрипты
3. **Wave 2 (measure-upstream):** Замерять upstream nixpkgs (холодный + тёплые), затем ОБЯЗАТЕЛЬНО откатить flake
4. **Wave 3 (measure-slim):** Замерять nixpkgs-slim (холодный + тёплые)
5. **Wave 4 (report):** Вычислить дельты, вывести таблицу, записать evidence
6. **Wave 5 (restore):** Вернуть исходный flake.nix и flake.lock

**Параллелизм:** Wave 0 и Wave 1 могут выполняться параллельно. Waves 2-3 строго последовательны (нужен только один flake.lock в момент времени). Wave 4 зависит от 2+3. Wave 5 — всегда.

**Критическое правило:** Wave 2 всегда завершается откатом flake.nix/flake.lock (T2.3) — даже если T2.2 упал с ошибкой. Без отката Wave 3 замерит не slim, а upstream.

---

## Todos

- [x] 1. Verify required tools (T0.1)
- [x] 2. Write find-equivalent-revision script (T1.0)
- [x] 3. Run find-equivalent-revision (T1.1)
- [x] 4. Create benchmark runner script (T1.2)
- [x] 5. Switch flake to upstream nixpkgs (T2.1)
- [x] 6. Lock and run upstream benchmark (T2.2)
- [x] 7. Revert flake to slim state (T2.3)
- [x] 8. Ensure slim flake is current (T3.1)
- [x] 9. Run slim benchmark (T3.2)
- [x] 10. Write comparison script (T4.0)
- [x] 11. Run comparison and display table (T4.1)
- [x] 12. Verify clean state (T5.1)

### Wave 0: Prerequisites check

#### T0.1: Verify required tools
**References:** This plan's Execution Strategy
**Acceptance:** All checks pass:
- `nix --version` outputs 2.18+ (regex: `2\.(1[8-9]|[2-9][0-9])`)
- `nix show-config | grep flakes` shows `experimental-features =` containing `flakes`
- `command -v time` succeeds (uses PATH, not `/usr/bin/time`)
- `python3 --version` outputs 3.x
- `nix eval '.#nixosConfigurations' --apply 'x: builtins.attrNames x'` includes `odin`
**QA happy:** All 5 checks pass, hostname `odin` confirmed
**QA failure:** Any check fails → print which tool is missing, abort with instructions
**Commit:** no commit (read-only)

### Wave 1: Prepare benchmark environment

#### T1.0: Write find-equivalent-revision script
**References:** `/etc/nixos/flake.lock` (node `nixpkgs_3`, field `locked.lastModified: 1784085041`)
**Acceptance:** Python script at `.omo/scripts/find-equiv-rev.py` (stdlib-only, no external deps) that:
- Reads target timestamp `1784085041` (from flake.lock nixpkgs_3.locked.lastModified)
- Queries `https://api.github.com/repos/NixOS/nixpkgs/commits?sha=nixos-unstable&until=<ISO8601>&per_page=1`
- Extracts the commit SHA whose `commit.committer.date` is closest to target
- Outputs the SHA to stdout
**QA happy:** Script runs, outputs 40-char hex SHA, `git ls-remote https://github.com/NixOS/nixpkgs.git $SHA` succeeds
**QA failure:** GitHub API rate-limited → fall back to `curl -sI https://github.com/NixOS/nixpkgs/commit/nixos-unstable | grep -i location` to extract latest unstable rev, use it with warning
**Commit:** `.omo/scripts/find-equiv-rev.py` (new file, committed with bench script)

#### T1.1: Run find-equivalent-revision
**References:** T1.0 (script), `/etc/nixos/flake.lock:lastModified`
**Acceptance:** `python3 .omo/scripts/find-equiv-rev.py` outputs a valid NixOS/nixpkgs commit SHA; `diff=$(( $(curl -s https://api.github.com/repos/NixOS/nixpkgs/commits/$SHA | jq .commit.committer.date | xargs -I{} date -d {} +%s) - 1784085041 )); [ ${diff#-} -le 3600 ]` passes
**QA happy:** SHA found, within 1h of target timestamp
**QA failure:** API down → use warning fallback from T1.0, record in evidence
**Commit:** no commit (read-only)

#### T1.2: Create benchmark runner script
**References:** This plan — metrics list in Scope, methodology in Verification Strategy
**Acceptance:** Script at `.omo/scripts/bench-nixpkgs.sh` that:
- Accepts `--variant slim|upstream` argument
- Runs `NIX_SHOW_STATS=1 nix eval '.#nixosConfigurations.odin.config.system.build.toplevel.name' 2> /tmp/stats-${variant}-${run_type}-${run_num}.json`
- Extracts wall time via `command time -p` (NOT `/usr/bin/time`)
- Parses JSON stats into CSV row
- Runs cold (after `rm -rf ~/.cache/nix/eval-cache-v* ~/.cache/nix/eval-cache.lock 2>/dev/null; nix eval --refresh ...` as extra safety) once
- Runs warm 3 times (no cache flush between)
- Outputs CSV to `/tmp/bench-${variant}.csv` (not stdout): header `variant,run_type,run_num,cpu_time,wall_time,values,thunks,sets_bytes,gc_time,gc_fraction,nrAvoided,nrLookups`
**QA happy:** Script executes without errors, `/tmp/bench-slim.csv` and `/tmp/bench-upstream.csv` exist after runs
**QA failure:** Script fails to parse NIX_SHOW_STATS JSON → print raw stderr to `.omo/evidence/bench-parse-error.log`, abort
**Commit:** `.omo/scripts/bench-nixpkgs.sh` (new file)

### Wave 2: Measure upstream nixpkgs

#### T2.1: Switch flake to upstream nixpkgs
**References:** `/etc/nixos/flake.nix` (`nixpkgs.url` line — find dynamically, not hardcoded line 8)
**Acceptance:** `sed -i 's|github:neg-serg/nixpkgs-slim/[a-f0-9]*|github:NixOS/nixpkgs/<REV>|' /etc/nixos/flake.nix` replaces the URL; `grep 'nixpkgs.url' /etc/nixos/flake.nix` shows `github:NixOS/nixpkgs/<REV>`
**QA happy:** `git diff flake.nix` shows exactly 1 line changed (the nixpkgs.url line)
**QA failure:** sed doesn't match → flake.nix format changed, abort
**Commit:** no separate commit (part of T2.3 cleanup)

#### T2.2: Lock and run upstream benchmark
**References:** T1.1 (upstream rev), T1.2 (bench script)
**Acceptance:** 
- `nix flake lock` succeeds (updates `flake.lock` to resolve upstream nixpkgs)
- `nix eval '.#nixosConfigurations.odin.config.system.build.toplevel.name'` outputs ANY string starting with `"nixos-system-odin-` (upstream uses different naming format than slim; exact rev substring not guaranteed)
- `.omo/scripts/bench-nixpkgs.sh --variant upstream` produces `/tmp/bench-upstream.csv` with 4 rows (1 cold + 3 warm)
**QA happy:** All 4 eval runs succeed, CSV has valid numeric values, `/tmp/bench-upstream.csv` exists with 5 lines (header + 4 data)
**QA failure (lock fail):** Record error output in `.omo/evidence/bench-upstream-lock-fail.log`, mark upstream as "N/A — lock failure", proceed to T2.3 then Wave 3
**QA failure (eval crash):** Record error output in `.omo/evidence/bench-upstream-fail.log`, mark upstream as "N/A — eval fails", proceed to T2.3 then Wave 3
**Commit:** no commit (dirty state preserved for T2.3)

#### T2.3: MANDATORY revert flake to slim state (runs even if T2.2 failed)
**References:** Original `flake.nix` and `flake.lock` in git HEAD
**Acceptance:** `GIT_MASTER=1 git checkout -- flake.nix flake.lock` restores original content; `GIT_MASTER=1 git diff --stat` is empty
**QA happy:** `grep 'nixpkgs.url' /etc/nixos/flake.nix` shows `neg-serg/nixpkgs-slim` again; git status clean
**QA failure:** checkout fails → `GIT_MASTER=1 git stash && GIT_MASTER=1 git checkout HEAD -- flake.nix flake.lock`, if still fails, abort with manual-restore instructions
**Commit:** no commit (git checkout is atomic rollback)

### Wave 3: Measure nixpkgs-slim fork

#### T3.1: Ensure slim flake is current
**References:** `/etc/nixos/flake.nix` (`nixpkgs.url` line)
**Acceptance:** `grep 'nixpkgs.url' /etc/nixos/flake.nix` shows `github:neg-serg/nixpkgs-slim/47ec8b0206b6307a2d458d388e4dd17a6aea8bdd`
**QA happy:** SHA matches; `nix flake lock` succeeds (or lock is already fresh from T2.3's checkout)
**QA failure:** SHA mismatch → flake was modified externally, `GIT_MASTER=1 git checkout -- flake.nix flake.lock` to restore
**Commit:** no commit (verify-only)

#### T3.2: Run slim benchmark
**References:** T1.2 (bench script)
**Acceptance:** `.omo/scripts/bench-nixpkgs.sh --variant slim` produces `/tmp/bench-slim.csv` with 4 rows (1 cold + 3 warm)
**QA happy:** All 4 eval runs succeed, CSV has valid numeric values, eval returns a string starting with `"nixos-system-odin-26.11.20260715.47ec8b0` (slim naming format)
**QA failure:** eval crash → blocking, record error in `.omo/evidence/bench-slim-fail.log`, abort
**Commit:** no commit (data collection only)

### Wave 4: Compare and report

#### T4.0: Write comparison script
**References:** `/tmp/bench-upstream.csv`, `/tmp/bench-slim.csv` (from T2.2, T3.2)
**Acceptance:** Python script at `.omo/scripts/compare-bench.py` (stdlib-only) that:
- Reads both CSV files
- Computes per-metric deltas: (slim - upstream) for warm-run means; negative = improvement
- Prints formatted terminal table with columns: Metric | Upstream (warm mean) | Slim (warm mean) | Delta | Δ%
- Writes same table in markdown to `.omo/evidence/bench-results.md`
- If upstream CSV is missing (eval crashed), prints "Upstream: N/A — eval failed" row and notes reason
**QA happy:** Terminal output is readable table; `.omo/evidence/bench-results.md` created
**QA failure:** CSV files missing → report which is absent, create evidence file with "N/A" markers
**Commit:** `.omo/scripts/compare-bench.py` (new file, committed with bench script)

#### T4.1: Run comparison and display
**References:** T4.0 (script)
**Acceptance:** `python3 .omo/scripts/compare-bench.py` runs, terminal table appears, `.omo/evidence/bench-results.md` exists with same table
**QA happy:** Table renders with aligned columns, delta % visible
**QA failure:** Terminal too narrow → output also to file, point user to it
**Commit:** `.omo/evidence/bench-results.md` (new evidence file)

### Wave 5: Cleanup

#### T5.1: Verify clean state
**References:** `/etc/nixos/flake.nix`, `/etc/nixos/flake.lock`
**Acceptance:** `GIT_MASTER=1 git status --short` is empty
**QA happy:** No modified files, original nixpkgs-slim pin present
**QA failure:** Dirty files remain → identify and report, offer to `git checkout`
**Commit:** no commit (verify-only)

---

## Final verification wave

- [x] F1. All measurements complete — CSV files exist with 4 rows each
- [x] F2. Deltas computed — bench-results.md exists with comparison table
- [x] F3. Flake restored to original state — git diff empty, nixpkgs.url shows slim
- [x] F4. No leftover benchmark artifacts — only .omo/ additions
- [x] F5. Warm-run variance acceptable — <10% for both variants

| Check | Method | Evidence |
|-------|--------|----------|
| F1: All measurements complete | CSV files exist with 4 rows each (or N/A documented) | `wc -l /tmp/bench-*.csv 2>/dev/null \|\| echo "upstream N/A"` |
| F2: Deltas computed | `bench-results.md` exists with comparison table | `grep 'Δ' .omo/evidence/bench-results.md` |
| F3: Flake restored to original state | `git diff --stat` empty, `nixpkgs.url` shows slim | `GIT_MASTER=1 git status --short` |
| F4: No leftover benchmark artifacts polluting repo | Only `.omo/` files changed, no temp files in `/etc/nixos/` | `GIT_MASTER=1 git status --short` |
| F5: Warm-run variance acceptable | Each variant's warm runs have <10% wall-time variance; if not, confidence LOW noted in report | `python3 -c "import csv; ..."` check |

---

## Commit strategy

**Single evidence commit (after Wave 4, before Wave 5):**
- `[perf] Add nixpkgs-slim vs upstream benchmark results`
- Files: `.omo/evidence/bench-results.md`, `.omo/plans/benchmark-nixpkgs-slim.md`, `.omo/scripts/bench-nixpkgs.sh`, `.omo/scripts/find-equiv-rev.py`, `.omo/scripts/compare-bench.py`

**No product-code commits:** `flake.nix` and `flake.lock` are rolled back via `git checkout`, not committed.

---

## Success criteria

1. Обе ветки замерены (или задокументирован crash upstream nixpkgs)
2. Таблица сравнения выведена в терминал
3. Таблица записана в `.omo/evidence/bench-results.md`
4. Исходный `flake.nix` и `flake.lock` восстановлены без изменений в истории
5. Все метрики имеют числовые значения (не NaN, не null)
